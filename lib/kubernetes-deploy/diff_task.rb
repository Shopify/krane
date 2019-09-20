# frozen_string_literal: true
require 'yaml'
require 'shellwords'
require 'tempfile'
require 'fileutils'

require 'kubernetes-deploy/common'
require 'kubernetes-deploy/concurrency'
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
require 'kubernetes-deploy/kubectl'
require 'kubernetes-deploy/kubeclient_builder'
require 'kubernetes-deploy/ejson_secret_provisioner'
require 'kubernetes-deploy/cluster_resource_discovery'
require 'kubernetes-deploy/template_sets'
require 'kubernetes-deploy/renderer'

module KubernetesDeploy
  class DiffTask
    def server_version
      kubectl.server_version
    end

    def initialize(
      namespace:, context:, current_sha:, logger: nil, kubectl_instance: nil, bindings: {},
      selector: nil, template_paths: [], template_dir: nil
    )
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
      @selector = selector
    end

    def run(*args)
      run!(*args)
      true
    rescue FatalDeploymentError
      false
    end

    def run!(stream: STDOUT)
      @logger.reset

      @logger.phase_heading("Validating resources")
      validate_configuration
      resources = discover_resources
      validate_resources(resources)

      @logger.phase_heading("Running diff")
      run_diff(resources, stream)

      @logger.print_summary(:success)
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

      resources.sort
    rescue InvalidTemplateError => e
      record_invalid_template(err: e.message, filename: e.filename, content: e.content)
      raise FatalDeploymentError, "Failed to render and parse template"
    end

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

    def validate_configuration()
      errors = []
      errors += kubeclient_builder.validate_config_files
      errors += @template_sets.validate

      if @namespace.blank?
        errors << "Namespace must be specified"
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
      @logger.info("Using resource selector #{@selector}") if @selector
      @namespace_tags |= tags_from_namespace_labels
      @logger.info("All required parameters and files are present")
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

    def with_retries(limit)
      retried = 0
      while retried <= limit
        success = yield
        break if success
        retried += 1
      end
    end

    def run_diff(resources, stream)
      return if resources.empty?

      if resources.length > 1
        @logger.info("Running diff for following resources:")
        resources.each do |r|
          @logger.info("- #{r.id}")
        end
      else
        resource = resources.first
        @logger.info("Running diff for following resource #{resource.id}")
      end

      # We want to diff resources 1-by-1 for readability
      resources.each do |r|
        run_string = ColorizedString.new("Running diff on #{r.type} #{r.namespace}.#{r.name}:").green
        @logger.blank_line
        @logger.info(run_string)
        output, err, diff_st = kubectl.run("diff", "-f", r.file_path, log_failure: true, fail_expected: true)

        if output.blank?
          no_diff_string = ColorizedString.new("Local and cluster versions are identical").yellow
          @logger.info(no_diff_string)
        end

        # Kubectl DIFF currently spits out exit code 1 in all cases - PR to customize that is open
        # https://github.com/kubernetes/kubernetes/pull/82336
        # next if diff_st.success?
        # raise FatalDeploymentError, <<~MSG
        #   Failed to replace or create resource: #{r.id}
        #   #{err}
        # MSG
        stream.puts output
      end
    end
  end
end
