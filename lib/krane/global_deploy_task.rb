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
    include Krane::TemplateReporting
    delegate :context, :logger, :global_kinds, to: :@task_config

    # Initializes the deploy task
    #
    # @param context [String] Kubernetes context
    # @param global_timeout [Integer] Timeout in seconds
    # @param selector [Hash] Selector(s) parsed by Krane::LabelSelector
    # @param template_paths [Array<String>] An array of template paths
    def initialize(context:, global_timeout: nil, selector: nil, filenames: [])
      template_paths = filenames.map { |path| File.expand_path(path) }

      @task_config = ::Krane::TaskConfig.new(context, nil)
      @template_sets = ::Krane::TemplateSets.from_dirs_and_files(paths: template_paths,
        logger: @task_config.logger)
      @global_timeout = global_timeout
      @selector = selector
    end

    # Runs the task, returning a boolean representing success or failure
    #
    # @return [Boolean]
    def run(*args)
      run!(*args)
      true
    rescue Krane::FatalDeploymentError
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
      validator = validate_configuration
      resources = discover_resources
      validator.validate_resources(resources, @selector)

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
      prune_whitelist = []
      resource_deployer = Krane::ResourceDeployer.new(task_config: @task_config,
        prune_whitelist: prune_whitelist, max_watch_seconds: @global_timeout,
        selector: @selector, statsd_tags: statsd_tags)
      resource_deployer.deploy!(resources, verify_result, prune)
    end

    def validate_configuration
      task_config_validator = Krane::GlobalDeployTaskConfigValidator.new(@task_config,
        kubectl, kubeclient_builder)
      errors = []
      errors += task_config_validator.errors
      errors += @template_sets.validate
      errors << "Selector is required" unless @selector.present?
      unless errors.empty?
        add_para_from_list(logger: logger, action: "Configuration invalid", enum: errors)
        raise Krane::TaskConfigurationError
      end

      logger.info("Using resource selector #{@selector}")
      logger.info("All required parameters and files are present")
      task_config_validator
    end
    measure_method(:validate_configuration)

    def discover_resources
      logger.info("Discovering resources:")
      resources = []
      crds_by_kind = cluster_resource_discoverer.crds.map { |crd| [crd.name, crd] }.to_h
      @template_sets.with_resource_definitions do |r_def|
        crd = crds_by_kind[r_def["kind"]]&.first
        r = Krane::KubernetesResource.build(context: context, logger: logger, definition: r_def,
          crd: crd, global_names: global_kinds, statsd_tags: statsd_tags)
        resources << r
        logger.info("  - #{r.id}")
      end

      resources.sort
    rescue Krane::InvalidTemplateError => e
      record_invalid_template(logger: logger, err: e.message, filename: e.filename, content: e.content)
      raise Krane::FatalDeploymentError, "Failed to parse template"
    end
    measure_method(:discover_resources)

    def cluster_resource_discoverer
      @cluster_resource_discoverer ||= Krane::ClusterResourceDiscovery.new(task_config: @task_config)
    end

    def statsd_tags
      %W(context:#{@context})
    end

    def kubectl
      @kubectl ||= Krane::Kubectl.new(task_config: @task_config, log_failure_by_default: true)
    end

    def kubeclient_builder
      @kubeclient_builder ||= Krane::KubeclientBuilder.new
    end

    def check_initial_status(resources)
      cache = Krane::ResourceCache.new(@task_config)
      Krane::Concurrency.split_across_threads(resources) { |r| r.sync(cache) }
      resources.each { |r| logger.info(r.pretty_status) }
    end
    measure_method(:check_initial_status, "initial_status.duration")
  end
end
