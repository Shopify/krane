# frozen_string_literal: true
require 'yaml'
require 'shellwords'
require 'tempfile'
require 'fileutils'

require 'kubernetes-deploy/common'
require 'kubernetes-deploy/concurrency'
require 'kubernetes-deploy/resource_cache'
require 'kubernetes-deploy/kubernetes_resource'
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
  require "kubernetes-deploy/kubernetes_resource/#{subresource}"
end
require 'kubernetes-deploy/resource_watcher'
require 'kubernetes-deploy/kubectl'
require 'kubernetes-deploy/kubeclient_builder'
require 'kubernetes-deploy/ejson_secret_provisioner'
require 'kubernetes-deploy/renderer'
require 'kubernetes-deploy/cluster_resource_discovery'
require 'kubernetes-deploy/template_sets'

module KubernetesDeploy
  class DeployTask
    extend KubernetesDeploy::StatsD::MeasureMethods

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
        batch/v1/Job
        extensions/v1beta1/ReplicaSet
        extensions/v1beta1/DaemonSet
        extensions/v1beta1/Deployment
        extensions/v1beta1/Ingress
        networking.k8s.io/v1/NetworkPolicy
        apps/v1beta1/StatefulSet
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

    def initialize(namespace:, context:, current_sha:, logger: nil, kubectl_instance: nil, bindings: {},
      max_watch_seconds: nil, selector: nil, template_paths: [], template_dir: nil)
      template_dir = File.expand_path(template_dir) if template_dir
      template_paths = (template_paths.map { |path| File.expand_path(path) } << template_dir).compact

      @logger = logger || KubernetesDeploy::FormattedLogger.build(namespace, context)
      @template_sets = TemplateSets.from_dirs_and_files(paths: template_paths, logger: @logger)
      @task_config = KubernetesDeploy::TaskConfig.new(context, namespace, @logger)
      @bindings = bindings
      @namespace = namespace
      @namespace_tags = []
      @context = context
      @current_sha = current_sha
      @kubectl = kubectl_instance
      @max_watch_seconds = max_watch_seconds
      @selector = selector
    end

    def run(*args)
      run!(*args)
      true
    rescue FatalDeploymentError
      false
    end

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
        predeploy_priority_resources(resources)
      end

      @logger.phase_heading("Deploying all resources")
      if PROTECTED_NAMESPACES.include?(@namespace) && prune
        raise FatalDeploymentError, "Refusing to deploy to protected namespace '#{@namespace}' with pruning enabled"
      end

      if verify_result
        deploy_all_resources(resources, prune: prune, verify: true)
        failed_resources = resources.reject(&:deploy_succeeded?)
        success = failed_resources.empty?
        if !success && failed_resources.all?(&:deploy_timed_out?)
          raise DeploymentTimeoutError
        end
        raise FatalDeploymentError unless success
      else
        deploy_all_resources(resources, prune: prune, verify: false)
        @logger.summary.add_action("deployed #{resources.length} #{'resource'.pluralize(resources.length)}")
        warning = <<~MSG
          Deploy result verification is disabled for this deploy.
          This means the desired changes were communicated to Kubernetes, but the deploy did not make sure they actually succeeded.
        MSG
        @logger.summary.add_paragraph(ColorizedString.new(warning).yellow)
      end
      StatsD.event("Deployment of #{@namespace} succeeded",
        "Successfully deployed all #{@namespace} resources to #{@context}",
        alert_type: "success", tags: statsd_tags << "status:success")
      StatsD.distribution('all_resources.duration', StatsD.duration(start), tags: statsd_tags << "status:success")
      @logger.print_summary(:success)
    rescue DeploymentTimeoutError
      @logger.print_summary(:timed_out)
      StatsD.event("Deployment of #{@namespace} timed out",
        "One or more #{@namespace} resources failed to deploy to #{@context} in time",
        alert_type: "error", tags: statsd_tags << "status:timeout")
      StatsD.distribution('all_resources.duration', StatsD.duration(start), tags: statsd_tags << "status:timeout")
      raise
    rescue FatalDeploymentError => error
      @logger.summary.add_action(error.message) if error.message != error.class.to_s
      @logger.print_summary(:failure)
      StatsD.event("Deployment of #{@namespace} failed",
        "One or more #{@namespace} resources failed to deploy to #{@context}",
        alert_type: "error", tags: statsd_tags << "status:failed")
      StatsD.distribution('all_resources.duration', StatsD.duration(start), tags: statsd_tags << "status:failed")
      raise
    end

    private

    def kubeclient_builder
      @kubeclient_builder ||= KubeclientBuilder.new
    end

    def cluster_resource_discoverer
      @cluster_resource_discoverer ||= ClusterResourceDiscovery.new(
        namespace: @namespace,
        context: @context,
        logger: @logger,
        namespace_tags: @namespace_tags
      )
    end

    def ejson_provisioners
      @ejson_provisoners ||= @template_sets.ejson_secrets_files.map do |ejson_secret_file|
        EjsonSecretProvisioner.new(
          namespace: @namespace,
          context: @context,
          ejson_keys_secret: ejson_keys_secret,
          ejson_file: ejson_secret_file,
          logger: @logger,
          statsd_tags: @namespace_tags,
          selector: @selector,
        )
      end
    end

    def deploy_has_priority_resources?(resources)
      resources.any? { |r| predeploy_sequence.include?(r.type) }
    end

    def predeploy_priority_resources(resource_list)
      bare_pods = resource_list.select { |resource| resource.is_a?(Pod) }
      if bare_pods.count == 1
        bare_pods.first.stream_logs = true
      end

      predeploy_sequence.each do |resource_type|
        matching_resources = resource_list.select { |r| r.type == resource_type }
        next if matching_resources.empty?
        deploy_resources(matching_resources, verify: true, record_summary: false)

        failed_resources = matching_resources.reject(&:deploy_succeeded?)
        fail_count = failed_resources.length
        if fail_count > 0
          KubernetesDeploy::Concurrency.split_across_threads(failed_resources) do |r|
            r.sync_debug_info(kubectl)
          end
          failed_resources.each { |r| @logger.summary.add_paragraph(r.debug_message) }
          raise FatalDeploymentError, "Failed to deploy #{fail_count} priority #{'resource'.pluralize(fail_count)}"
        end
        @logger.blank_line
      end
    end
    measure_method(:predeploy_priority_resources, 'priority_resources.duration')

    def validate_resources(resources)
      KubernetesDeploy::Concurrency.split_across_threads(resources) do |r|
        r.validate_definition(kubectl, selector: @selector)
      end

      resources.select(&:has_warnings?).each do |resource|
        record_warnings(warning: resource.validation_warning_msg, filename: File.basename(resource.file_path))
      end

      failed_resources = resources.select(&:validation_failed?)
      return unless failed_resources.present?

      failed_resources.each do |r|
        content = File.read(r.file_path) if File.file?(r.file_path) && !r.sensitive_template_content?
        record_invalid_template(err: r.validation_error_msg, filename: File.basename(r.file_path), content: content)
      end
      raise FatalDeploymentError, "Template validation failed"
    end
    measure_method(:validate_resources)

    def check_initial_status(resources)
      cache = ResourceCache.new(@namespace, @context, @logger)
      KubernetesDeploy::Concurrency.split_across_threads(resources) { |r| r.sync(cache) }
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
      @template_sets.with_resource_definitions(render_erb: true,
          current_sha: @current_sha, bindings: @bindings) do |r_def|
        crd = crds_by_kind[r_def["kind"]]&.first
        r = KubernetesResource.build(namespace: @namespace, context: @context, logger: @logger, definition: r_def,
          statsd_tags: @namespace_tags, crd: crd)
        resources << r
        @logger.info("  - #{r.id}")
      end

      secrets_from_ejson.each do |secret|
        resources << secret
        @logger.info("  - #{secret.id} (from ejson)")
      end

      if (global = resources.select(&:global?).presence)
        @logger.warn("Detected non-namespaced #{'resource'.pluralize(global.count)} which will never be pruned:")
        global.each { |r| @logger.warn("  - #{r.id}") }
      end
      resources.sort
    rescue InvalidTemplateError => e
      record_invalid_template(err: e.message, filename: e.filename, content: e.content)
      raise FatalDeploymentError, "Failed to render and parse template"
    end
    measure_method(:discover_resources)

    def record_invalid_template(err:, filename:, content: nil)
      debug_msg = ColorizedString.new("Invalid template: #{filename}\n").red
      debug_msg += "> Error message:\n#{FormattedLogger.indent_four(err)}"
      if content
        debug_msg += if content =~ /kind:\s*Secret/
          "\n> Template content: Suppressed because it may contain a Secret"
        else
          "\n> Template content:\n#{FormattedLogger.indent_four(content)}"
        end
      end
      @logger.summary.add_paragraph(debug_msg)
    end

    def record_warnings(warning:, filename:)
      warn_msg = "Template warning: #{filename}\n"
      warn_msg += "> Warning message:\n#{FormattedLogger.indent_four(warning)}"
      @logger.summary.add_paragraph(ColorizedString.new(warn_msg).yellow)
    end

    def validate_configuration(allow_protected_ns:, prune:)
      errors = []
      errors += kubeclient_builder.validate_config_files
      errors += @template_sets.validate

      if @namespace.blank?
        errors << "Namespace must be specified"
      elsif PROTECTED_NAMESPACES.include?(@namespace)
        if allow_protected_ns && prune
          errors << "Refusing to deploy to protected namespace '#{@namespace}' with pruning enabled"
        elsif allow_protected_ns
          @logger.warn("You're deploying to protected namespace #{@namespace}, which cannot be pruned.")
          @logger.warn("Existing resources can only be removed manually with kubectl. " \
            "Removing templates from the set deployed will have no effect.")
          @logger.warn("***Please do not deploy to #{@namespace} unless you really know what you are doing.***")
        else
          errors << "Refusing to deploy to protected namespace '#{@namespace}'"
        end
      end

      if @context.blank?
        errors << "Context must be specified"
      end

      unless errors.empty?
        @logger.summary.add_paragraph(errors.map { |err| "- #{err}" }.join("\n"))
        raise FatalDeploymentError, "Configuration invalid"
      end

      confirm_context_exists
      confirm_namespace_exists
      confirm_ejson_keys_not_prunable if prune
      @logger.info("Using resource selector #{@selector}") if @selector
      @namespace_tags |= tags_from_namespace_labels
      @logger.info("All required parameters and files are present")
    end
    measure_method(:validate_configuration)

    def deploy_resources(resources, prune: false, verify:, record_summary: true)
      return if resources.empty?
      deploy_started_at = Time.now.utc

      if resources.length > 1
        @logger.info("Deploying resources:")
        resources.each do |r|
          @logger.info("- #{r.id} (#{r.pretty_timeout_type})")
        end
      else
        resource = resources.first
        @logger.info("Deploying #{resource.id} (#{resource.pretty_timeout_type})")
      end

      # Apply can be done in one large batch, the rest have to be done individually
      applyables, individuals = resources.partition { |r| r.deploy_method == :apply }
      # Prunable resources should also applied so that they can  be pruned
      pruneable_types = prune_whitelist.map { |t| t.split("/").last }
      applyables += individuals.select { |r| pruneable_types.include?(r.type) }

      individuals.each do |r|
        r.deploy_started_at = Time.now.utc
        case r.deploy_method
        when :replace
          _, _, replace_st = kubectl.run("replace", "-f", r.file_path, log_failure: false)
        when :replace_force
          _, _, replace_st = kubectl.run("replace", "--force", "--cascade", "-f", r.file_path,
            log_failure: false)
        else
          # Fail Fast! This is a programmer mistake.
          raise ArgumentError, "Unexpected deploy method! (#{r.deploy_method.inspect})"
        end

        next if replace_st.success?
        # it doesn't exist so we can't replace it
        _, err, create_st = kubectl.run("create", "-f", r.file_path, log_failure: false)

        next if create_st.success?
        raise FatalDeploymentError, <<~MSG
          Failed to replace or create resource: #{r.id}
          #{err}
        MSG
      end

      apply_all(applyables, prune)

      if verify
        watcher = ResourceWatcher.new(resources: resources, logger: @logger, deploy_started_at: deploy_started_at,
          timeout: @max_watch_seconds, namespace: @namespace, context: @context, sha: @current_sha)
        watcher.run(record_summary: record_summary)
      end
    end

    def deploy_all_resources(resources, prune: false, verify:, record_summary: true)
      deploy_resources(resources, prune: prune, verify: verify, record_summary: record_summary)
    end
    measure_method(:deploy_all_resources, 'normal_resources.duration')

    def apply_all(resources, prune)
      return unless resources.present?
      command = %w(apply)

      Dir.mktmpdir do |tmp_dir|
        resources.each do |r|
          FileUtils.symlink(r.file_path, tmp_dir)
          r.deploy_started_at = Time.now.utc
        end
        command.push("-f", tmp_dir)

        if prune
          command.push("--prune")
          if @selector
            command.push("--selector", @selector.to_s)
          else
            command.push("--all")
          end
          prune_whitelist.each { |type| command.push("--prune-whitelist=#{type}") }
        end

        output_is_sensitive = resources.any?(&:sensitive_template_content?)
        out, err, st = kubectl.run(*command, log_failure: false, output_is_sensitive: output_is_sensitive)

        if st.success?
          log_pruning(out) if prune
        else
          record_apply_failure(err, resources: resources)
          raise FatalDeploymentError, "Command failed: #{Shellwords.join(command)}"
        end
      end
    end
    measure_method(:apply_all)

    def log_pruning(kubectl_output)
      pruned = kubectl_output.scan(/^(.*) pruned$/)
      return unless pruned.present?

      @logger.info("The following resources were pruned: #{pruned.join(', ')}")
      @logger.summary.add_action("pruned #{pruned.length} #{'resource'.pluralize(pruned.length)}")
    end

    def record_apply_failure(err, resources: [])
      warn_msg = "WARNING: Any resources not mentioned in the error(s) below were likely created/updated. " \
        "You may wish to roll back this deploy."
      @logger.summary.add_paragraph(ColorizedString.new(warn_msg).yellow)

      unidentified_errors = []
      filenames_with_sensitive_content = resources
        .select(&:sensitive_template_content?)
        .map { |r| File.basename(r.file_path) }

      err.each_line do |line|
        bad_files = find_bad_files_from_kubectl_output(line)
        if bad_files.present?
          bad_files.each do |f|
            if filenames_with_sensitive_content.include?(f[:filename])
              # Hide the error and template contents in case it has senitive information
              record_invalid_template(err: "SUPPRESSED FOR SECURITY", filename: f[:filename], content: nil)
            else
              record_invalid_template(err: f[:err], filename: f[:filename], content: f[:content])
            end
          end
        else
          unidentified_errors << line
        end
      end

      if unidentified_errors.present? && filenames_with_sensitive_content.any?
        warn_msg = "WARNING: There was an error applying some or all resources. The raw output may be sensitive and " \
          "so cannot be displayed."
        @logger.summary.add_paragraph(ColorizedString.new(warn_msg).yellow)
      elsif unidentified_errors.present?
        heading = ColorizedString.new('Unidentified error(s):').red
        msg = FormattedLogger.indent_four(unidentified_errors.join)
        @logger.summary.add_paragraph("#{heading}\n#{msg}")
      end
    end

    # Inspect the file referenced in the kubectl stderr
    # to make it easier for developer to understand what's going on
    def find_bad_files_from_kubectl_output(line)
      # stderr often contains one or more lines like the following, from which we can extract the file path(s):
      # Error from server (TypeOfError): error when creating "/path/to/service-gqq5oh.yml": Service "web" is invalid:

      line.scan(%r{"(/\S+\.ya?ml\S*)"}).each_with_object([]) do |matches, bad_files|
        matches.each do |path|
          content = File.read(path) if File.file?(path)
          bad_files << { filename: File.basename(path), err: line, content: content }
        end
      end
    end

    def confirm_context_exists
      out, err, st = kubectl.run("config", "get-contexts", "-o", "name",
        use_namespace: false, use_context: false, log_failure: false)
      available_contexts = out.split("\n")
      if !st.success?
        raise FatalDeploymentError, err
      elsif !available_contexts.include?(@context)
        raise FatalDeploymentError, "Context #{@context} is not available. Valid contexts: #{available_contexts}"
      end
      confirm_cluster_reachable
      @logger.info("Context #{@context} found")
    end

    def confirm_cluster_reachable
      success = false
      with_retries(2) do
        begin
          success = kubectl.version_info
        rescue KubectlError
          success = false
        end
      end
      raise FatalDeploymentError, "Failed to reach server for #{@context}" unless success
      TaskConfigValidator.new(@task_config, kubectl, kubeclient_builder, only: [:validate_server_version]).valid?
    end

    def confirm_namespace_exists
      raise FatalDeploymentError, "Namespace #{@namespace} not found" unless namespace_definition.present?
      @logger.info("Namespace #{@namespace} found")
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
      @kubectl ||= Kubectl.new(namespace: @namespace, context: @context, logger: @logger, log_failure_by_default: true)
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
