# frozen_string_literal: true
require 'yaml'
require 'shellwords'
require 'tempfile'
require 'fileutils'

require 'krane/common'
require 'krane/concurrency'
require 'krane/resource_cache'
require 'krane/kubernetes_resource'
%w(
  custom_resource
  cloudsql
  config_map
  deployment
  ingress
  persistent_volume_claim
  pod
  network_policy
  service
  pod_template
  pod_disruption_budget
  replica_set
  service_account
  daemon_set
  resource_quota
  stateful_set
  cron_job
  job
  custom_resource_definition
  horizontal_pod_autoscaler
  secret
).each do |subresource|
  require "krane/kubernetes_resource/#{subresource}"
end
require 'krane/resource_watcher'
require 'krane/kubectl'
require 'krane/kubeclient_builder'
require 'krane/ejson_secret_provisioner'
require 'krane/renderer'
require 'krane/cluster_resource_discovery'
require 'krane/template_sets'
require 'krane/deploy_task_config_validator'
require 'krane/resource_deployer'
require 'krane/concerns/template_reporting'

module Krane
  # Ship resources to a namespace
  class DeprecatedDeployTask
    extend Krane::StatsD::MeasureMethods
    include Krane::TemplateReporting

    PROTECTED_NAMESPACES = %w(
      default
      kube-system
      kube-public
    )
    # Things removed from default prune whitelist at https://github.com/kubernetes/kubernetes/blob/0dff56b4d88ec7551084bf89028dbeebf569620e/pkg/kubectl/cmd/apply.go#L411:
    # core/v1/Namespace -- not namespaced
    # core/v1/PersistentVolume -- not namespaced
    # core/v1/Endpoints -- managed by services
    # core/v1/PersistentVolumeClaim -- would delete data
    # core/v1/ReplicationController -- superseded by deployments/replicasets

    def predeploy_sequence
      before_crs = %w(
        ResourceQuota
        NetworkPolicy
      )
      after_crs = %w(
        ConfigMap
        PersistentVolumeClaim
        ServiceAccount
        Role
        RoleBinding
        Secret
        Pod
      )

      before_crs + cluster_resource_discoverer.crds.select(&:predeployed?).map(&:kind) + after_crs
    end

    def prune_whitelist
      wl = %w(
        core/v1/ConfigMap
        core/v1/Pod
        core/v1/Service
        core/v1/ResourceQuota
        core/v1/Secret
        core/v1/ServiceAccount
        core/v1/PodTemplate
        core/v1/PersistentVolumeClaim
        batch/v1/Job
        apps/v1/ReplicaSet
        apps/v1/DaemonSet
        apps/v1/Deployment
        extensions/v1beta1/Ingress
        networking.k8s.io/v1/NetworkPolicy
        apps/v1/StatefulSet
        autoscaling/v1/HorizontalPodAutoscaler
        policy/v1beta1/PodDisruptionBudget
        batch/v1beta1/CronJob
        rbac.authorization.k8s.io/v1/Role
        rbac.authorization.k8s.io/v1/RoleBinding
      )
      wl + cluster_resource_discoverer.crds.select(&:prunable?).map(&:group_version_kind)
    end

    def server_version
      kubectl.server_version
    end

    # Initializes the deploy task
    #
    # @param namespace [String] Kubernetes namespace
    # @param context [String] Kubernetes context
    # @param current_sha [String] The SHA of the commit
    # @param logger [Object] Logger object (defaults to an instance of Krane::FormattedLogger)
    # @param kubectl_instance [Kubectl] Kubectl instance
    # @param bindings [Hash] Bindings parsed by Krane::BindingsParser
    # @param max_watch_seconds [Integer] Timeout in seconds
    # @param selector [Hash] Selector(s) parsed by Krane::LabelSelector
    # @param template_paths [Array<String>] An array of template paths
    # @param template_dir [String] Path to a directory with templates (deprecated)
    # @param protected_namespaces [Array<String>] Array of protected Kubernetes namespaces (defaults
    #   to Krane::DeployTask::PROTECTED_NAMESPACES)
    # @param render_erb [Boolean] Enable ERB rendering
    def initialize(namespace:, context:, current_sha:, logger: nil, kubectl_instance: nil, bindings: {},
      max_watch_seconds: nil, selector: nil, template_paths: [], template_dir: nil, protected_namespaces: nil,
      render_erb: true, allow_globals: false)
      template_dir = File.expand_path(template_dir) if template_dir
      template_paths = (template_paths.map { |path| File.expand_path(path) } << template_dir).compact

      @logger = logger || Krane::FormattedLogger.build(namespace, context)
      @template_sets = TemplateSets.from_dirs_and_files(paths: template_paths, logger: @logger)
      @task_config = Krane::TaskConfig.new(context, namespace, @logger)
      @bindings = bindings
      @namespace = namespace
      @namespace_tags = []
      @context = context
      @current_sha = current_sha
      @kubectl = kubectl_instance
      @max_watch_seconds = max_watch_seconds
      @selector = selector
      @protected_namespaces = protected_namespaces || PROTECTED_NAMESPACES
      @render_erb = render_erb
      @allow_globals = allow_globals
    end

    # Runs the task, returning a boolean representing success or failure
    #
    # @return [Boolean]
    def run(*args)
      run!(*args)
      true
    rescue FatalDeploymentError
      false
    end

    # Runs the task, raising exceptions in case of issues
    #
    # @param verify_result [Boolean] Wait for completion and verify success
    # @param allow_protected_ns [Boolean] Enable deploying to protected namespaces
    # @param prune [Boolean] Enable deletion of resources that do not appear in the template dir
    #
    # @return [nil]
    def run!(verify_result: true, allow_protected_ns: false, prune: true)
      start = Time.now.utc
      @logger.reset

      @logger.phase_heading("Initializing deploy")
      validate_configuration(allow_protected_ns: allow_protected_ns, prune: prune)
      resources = discover_resources
      validate_resources(resources)

      @logger.phase_heading("Checking initial resource statuses")
      check_initial_status(resources)

      if deploy_has_priority_resources?(resources)
        @logger.phase_heading("Predeploying priority resources")
        resource_deployer.predeploy_priority_resources(resources, predeploy_sequence)
      end

      @logger.phase_heading("Deploying all resources")
      if @protected_namespaces.include?(@namespace) && prune
        raise FatalDeploymentError, "Refusing to deploy to protected namespace '#{@namespace}' with pruning enabled"
      end

      resource_deployer.deploy!(resources, verify_result, prune)

      StatsD.client.event("Deployment of #{@namespace} succeeded",
        "Successfully deployed all #{@namespace} resources to #{@context}",
        alert_type: "success", tags: statsd_tags + %w(status:success))
      StatsD.client.distribution('all_resources.duration', StatsD.duration(start),
        tags: statsd_tags + %w(status:success))
      @logger.print_summary(:success)
    rescue DeploymentTimeoutError
      @logger.print_summary(:timed_out)
      StatsD.client.event("Deployment of #{@namespace} timed out",
        "One or more #{@namespace} resources failed to deploy to #{@context} in time",
        alert_type: "error", tags: statsd_tags + %w(status:timeout))
      StatsD.client.distribution('all_resources.duration', StatsD.duration(start),
        tags: statsd_tags + %w(status:timeout))
      raise
    rescue FatalDeploymentError => error
      @logger.summary.add_action(error.message) if error.message != error.class.to_s
      @logger.print_summary(:failure)
      StatsD.client.event("Deployment of #{@namespace} failed",
        "One or more #{@namespace} resources failed to deploy to #{@context}",
        alert_type: "error", tags: statsd_tags + %w(status:failed))
      StatsD.client.distribution('all_resources.duration', StatsD.duration(start),
        tags: statsd_tags + %w(status:failed))
      raise
    end

    private

    def resource_deployer
      @resource_deployer ||= Krane::ResourceDeployer.new(task_config: @task_config,
        prune_whitelist: prune_whitelist, max_watch_seconds: @max_watch_seconds,
        selector: @selector, statsd_tags: statsd_tags, current_sha: @current_sha)
    end

    def kubeclient_builder
      @kubeclient_builder ||= KubeclientBuilder.new
    end

    def cluster_resource_discoverer
      @cluster_resource_discoverer ||= ClusterResourceDiscovery.new(
        task_config: @task_config,
        namespace_tags: @namespace_tags
      )
    end

    def ejson_provisioners
      @ejson_provisoners ||= @template_sets.ejson_secrets_files.map do |ejson_secret_file|
        EjsonSecretProvisioner.new(
          task_config: @task_config,
          ejson_keys_secret: ejson_keys_secret,
          ejson_file: ejson_secret_file,
          statsd_tags: @namespace_tags,
          selector: @selector,
        )
      end
    end

    def deploy_has_priority_resources?(resources)
      resources.any? { |r| predeploy_sequence.include?(r.type) }
    end

    def check_initial_status(resources)
      cache = ResourceCache.new(@task_config)
      Krane::Concurrency.split_across_threads(resources) { |r| r.sync(cache) }
      resources.each { |r| @logger.info(r.pretty_status) }
    end
    measure_method(:check_initial_status, "initial_status.duration")

    def secrets_from_ejson
      ejson_provisioners.flat_map(&:resources)
    end

    def discover_resources
      @logger.info("Discovering resources:")
      resources = []
      crds_by_kind = cluster_resource_discoverer.crds.group_by(&:kind)
      @template_sets.with_resource_definitions(render_erb: @render_erb,
          current_sha: @current_sha, bindings: @bindings) do |r_def|
        crd = crds_by_kind[r_def["kind"]]&.first
        r = KubernetesResource.build(namespace: @namespace, context: @context, logger: @logger, definition: r_def,
          statsd_tags: @namespace_tags, crd: crd, global_names: @task_config.global_kinds)
        resources << r
        @logger.info("  - #{r.id}")
      end

      secrets_from_ejson.each do |secret|
        resources << secret
        @logger.info("  - #{secret.id} (from ejson)")
      end

      resources.sort
    rescue InvalidTemplateError => e
      record_invalid_template(logger: @logger, err: e.message, filename: e.filename,
         content: e.content)
      raise FatalDeploymentError, "Failed to render and parse template"
    end
    measure_method(:discover_resources)

    def validate_configuration(allow_protected_ns:, prune:)
      task_config_validator = DeployTaskConfigValidator.new(@protected_namespaces, allow_protected_ns, prune,
        @task_config, kubectl, kubeclient_builder)
      errors = []
      errors += task_config_validator.errors
      errors += @template_sets.validate
      unless errors.empty?
        add_para_from_list(logger: @logger, action: "Configuration invalid", enum: errors)
        raise Krane::TaskConfigurationError
      end

      confirm_ejson_keys_not_prunable if prune
      @logger.info("Using resource selector #{@selector}") if @selector
      @namespace_tags |= tags_from_namespace_labels
      @logger.info("All required parameters and files are present")
    end
    measure_method(:validate_configuration)

    def validate_resources(resources)
      Krane::Concurrency.split_across_threads(resources) do |r|
        r.validate_definition(kubectl, selector: @selector)
      end

      resources.select(&:has_warnings?).each do |resource|
        record_warnings(logger: @logger, warning: resource.validation_warning_msg,
          filename: File.basename(resource.file_path))
      end

      failed_resources = resources.select(&:validation_failed?)
      if failed_resources.present?

        failed_resources.each do |r|
          content = File.read(r.file_path) if File.file?(r.file_path) && !r.sensitive_template_content?
          record_invalid_template(logger: @logger, err: r.validation_error_msg,
            filename: File.basename(r.file_path), content: content)
        end
        raise FatalDeploymentError, "Template validation failed"
      end
      validate_globals(resources)
    end
    measure_method(:validate_resources)

    def validate_globals(resources)
      return unless (global = resources.select(&:global?).presence)
      global_names = global.map do |resource|
        "#{resource.name} (#{resource.type}) in #{File.basename(resource.file_path)}"
      end
      global_names = FormattedLogger.indent_four(global_names.join("\n"))

      if @allow_globals
        msg = "The ability for this task to deploy global resources will be removed in the next version,"\
              " which will affect the following resources:"
        msg += "\n#{global_names}"
        @logger.summary.add_paragraph(ColorizedString.new(msg).yellow)
      else
        @logger.summary.add_paragraph(ColorizedString.new("Global resources:\n#{global_names}").yellow)
        raise FatalDeploymentError, "This command is namespaced and cannot be used to deploy global resources."
      end
    end

    def namespace_definition
      @namespace_definition ||= begin
        definition, _err, st = kubectl.run("get", "namespace", @namespace, use_namespace: false,
          log_failure: true, raise_if_not_found: true, attempts: 3, output: 'json')
        st.success? ? JSON.parse(definition, symbolize_names: true) : nil
      end
    rescue Kubectl::ResourceNotFoundError
      nil
    end

    # make sure to never prune the ejson-keys secret
    def confirm_ejson_keys_not_prunable
      return unless ejson_keys_secret.dig("metadata", "annotations", KubernetesResource::LAST_APPLIED_ANNOTATION)

      @logger.error("Deploy cannot proceed because protected resource " \
        "Secret/#{EjsonSecretProvisioner::EJSON_KEYS_SECRET} would be pruned.")
      raise EjsonPrunableError
    rescue Kubectl::ResourceNotFoundError => e
      @logger.debug("Secret/#{EjsonSecretProvisioner::EJSON_KEYS_SECRET} does not exist: #{e}")
    end

    def tags_from_namespace_labels
      return [] if namespace_definition.blank?
      namespace_labels = namespace_definition.fetch(:metadata, {}).fetch(:labels, {})
      namespace_labels.map { |key, value| "#{key}:#{value}" }
    end

    def kubectl
      @kubectl ||= Kubectl.new(task_config: @task_config, log_failure_by_default: true)
    end

    def ejson_keys_secret
      @ejson_keys_secret ||= begin
        out, err, st = kubectl.run("get", "secret", EjsonSecretProvisioner::EJSON_KEYS_SECRET, output: "json",
          raise_if_not_found: true, attempts: 3, output_is_sensitive: true, log_failure: true)
        unless st.success?
          raise EjsonSecretError, "Error retrieving Secret/#{EjsonSecretProvisioner::EJSON_KEYS_SECRET}: #{err}"
        end
        JSON.parse(out)
      end
    end

    def statsd_tags
      %W(namespace:#{@namespace} sha:#{@current_sha} context:#{@context}) | @namespace_tags
    end

    def with_retries(limit)
      retried = 0
      while retried <= limit
        success = yield
        break if success
        retried += 1
      end
    end
  end
end
