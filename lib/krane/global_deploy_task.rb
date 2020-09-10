# frozen_string_literal: true
require 'tempfile'

require 'krane/common'
require 'krane/concurrency'
require 'krane/resource_cache'
require 'krane/kubectl'
require 'krane/kubeclient_builder'
require 'krane/cluster_resource_discovery'
require 'krane/template_sets'
require 'krane/resource_deployer'
require 'krane/kubernetes_resource'
require 'krane/global_deploy_task_config_validator'
require 'krane/concerns/template_reporting'

%w(
  custom_resource
  custom_resource_definition
).each do |subresource|
  require "krane/kubernetes_resource/#{subresource}"
end

module Krane
  # Ship global resources to a context
  class GlobalDeployTask
    extend Krane::StatsD::MeasureMethods
    include TemplateReporting
    delegate :context, :logger, :global_kinds, :kubeclient_builder, to: :@task_config
    attr_reader :task_config

    # Initializes the deploy task
    #
    # @param context [String] Kubernetes context (*required*)
    # @param global_timeout [Integer] Timeout in seconds
    # @param selector [Hash] Selector(s) parsed by Krane::LabelSelector (*required*)
    # @param filenames [Array<String>] An array of filenames and/or directories containing templates (*required*)
    def initialize(context:, global_timeout: nil, selector: nil, filenames: [], logger: nil, kubeconfig: nil)
      template_paths = filenames.map { |path| File.expand_path(path) }

      @task_config = TaskConfig.new(context, nil, logger, kubeconfig)
      @template_sets = TemplateSets.from_dirs_and_files(paths: template_paths,
        logger: @task_config.logger, render_erb: false)
      @global_timeout = global_timeout
      @selector = selector
    end

    # Runs the task, returning a boolean representing success or failure
    #
    # @return [Boolean]
    def run(**args)
      run!(**args)
      true
    rescue FatalDeploymentError
      false
    end

    # Runs the task, raising exceptions in case of issues
    #
    # @param verify_result [Boolean] Wait for completion and verify success
    # @param prune [Boolean] Enable deletion of resources that match the provided
    #  selector and do not appear in the template dir
    #
    # @return [nil]
    def run!(verify_result: true, prune: true)
      start = Time.now.utc
      logger.reset

      logger.phase_heading("Initializing deploy")
      validate_configuration
      resources = discover_resources
      validate_resources(resources)

      logger.phase_heading("Checking initial resource statuses")
      check_initial_status(resources)

      logger.phase_heading("Deploying all resources")
      deploy!(resources, verify_result, prune)

      StatsD.client.event("Deployment succeeded",
        "Successfully deployed all resources to #{context}",
        alert_type: "success", tags: statsd_tags + %w(status:success))
      StatsD.client.distribution('all_resources.duration', StatsD.duration(start),
        tags: statsd_tags << "status:success")
      logger.print_summary(:success)
    rescue Krane::DeploymentTimeoutError
      logger.print_summary(:timed_out)
      StatsD.client.event("Deployment timed out",
        "One or more resources failed to deploy to #{context} in time",
        alert_type: "error", tags: statsd_tags + %w(status:timeout))
      StatsD.client.distribution('all_resources.duration', StatsD.duration(start),
        tags: statsd_tags << "status:timeout")
      raise
    rescue Krane::FatalDeploymentError => error
      logger.summary.add_action(error.message) if error.message != error.class.to_s
      logger.print_summary(:failure)
      StatsD.client.event("Deployment failed",
        "One or more resources failed to deploy to #{context}",
        alert_type: "error", tags: statsd_tags + %w(status:failed))
      StatsD.client.distribution('all_resources.duration', StatsD.duration(start),
        tags: statsd_tags << "status:failed")
      raise
    end

    private

    def deploy!(resources, verify_result, prune)
      resource_deployer = ResourceDeployer.new(task_config: @task_config,
        prune_whitelist: prune_whitelist, global_timeout: @global_timeout,
        selector: @selector, statsd_tags: statsd_tags)
      resource_deployer.deploy!(resources, verify_result, prune)
    end

    def validate_configuration
      task_config_validator = GlobalDeployTaskConfigValidator.new(@task_config,
        kubectl, kubeclient_builder)
      errors = []
      errors += task_config_validator.errors
      errors += @template_sets.validate
      errors << "Selector is required" unless @selector.to_h.present?
      unless errors.empty?
        add_para_from_list(logger: logger, action: "Configuration invalid", enum: errors)
        raise TaskConfigurationError
      end

      logger.info("Using resource selector #{@selector}")
      logger.info("All required parameters and files are present")
    end
    measure_method(:validate_configuration)

    def validate_resources(resources)
      validate_globals(resources)

      Concurrency.split_across_threads(resources) do |r|
        r.validate_definition(@kubectl, selector: @selector)
      end

      failed_resources = resources.select(&:validation_failed?)
      if failed_resources.present?
        failed_resources.each do |r|
          content = File.read(r.file_path) if File.file?(r.file_path) && !r.sensitive_template_content?
          record_invalid_template(logger: logger, err: r.validation_error_msg,
            filename: File.basename(r.file_path), content: content)
        end
        raise FatalDeploymentError, "Template validation failed"
      end
    end
    measure_method(:validate_resources)

    def validate_globals(resources)
      return unless (namespaced = resources.reject(&:global?).presence)
      namespaced_names = namespaced.map do |resource|
        "#{resource.name} (#{resource.type}) in #{File.basename(resource.file_path)}"
      end
      namespaced_names = FormattedLogger.indent_four(namespaced_names.join("\n"))

      logger.summary.add_paragraph(ColorizedString.new("Namespaced resources:\n#{namespaced_names}").yellow)
      raise FatalDeploymentError, "This command cannot deploy namespaced resources. Use DeployTask instead."
    end

    def discover_resources
      logger.info("Discovering resources:")
      resources = []
      crds_by_kind = cluster_resource_discoverer.crds.map { |crd| [crd.name, crd] }.to_h
      @template_sets.with_resource_definitions do |r_def|
        crd = crds_by_kind[r_def["kind"]]&.first
        r = KubernetesResource.build(context: context, logger: logger, definition: r_def,
          crd: crd, global_names: global_kinds, statsd_tags: statsd_tags)
        resources << r
        logger.info("  - #{r.id}")
      end

      StatsD.client.gauge('discover_resources.count', resources.size, tags: statsd_tags)

      resources.sort
    rescue InvalidTemplateError => e
      record_invalid_template(logger: logger, err: e.message, filename: e.filename, content: e.content)
      raise FatalDeploymentError, "Failed to parse template"
    end
    measure_method(:discover_resources)

    def cluster_resource_discoverer
      @cluster_resource_discoverer ||= ClusterResourceDiscovery.new(task_config: @task_config)
    end

    def statsd_tags
      %W(context:#{context})
    end

    def kubectl
      @kubectl ||= Kubectl.new(task_config: @task_config, log_failure_by_default: true)
    end

    def prune_whitelist
      cluster_resource_discoverer.prunable_resources(namespaced: false)
    end

    def check_initial_status(resources)
      cache = ResourceCache.new(@task_config)
      cache.prewarm(resources)
      Concurrency.split_across_threads(resources) { |r| r.sync(cache) }
      resources.each { |r| logger.info(r.pretty_status) }
    end
    measure_method(:check_initial_status, "initial_status.duration")
  end
end
