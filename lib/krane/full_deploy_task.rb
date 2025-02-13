# frozen_string_literal: true

module Krane
  class FullDeployTask
    extend Krane::StatsD::MeasureMethods
    include TemplateReporting
    delegate :context, :logger, :global_kinds, :kubeclient_builder, to: :@task_config
    attr_reader :task_config

    # Initializes the deploy task
    #
    # @param namespace [String] Kubernetes namespace (*required*)
    # @param context [String] Kubernetes context (*required*)
    # @param global_timeout [Integer] Timeout in seconds
    # @param global_selector [Hash] Global selector(s) parsed by Krane::LabelSelector (*required*)
    # @param global_selector_as_filter [Boolean] Allow selecting a subset of Kubernetes resource during global deploy
    # @param selector [Hash] Selector(s) parsed by Krane::LabelSelector (*required*)
    # @param selector_as_filter [Boolean] Allow selecting a subset of Kubernetes resource templates to deploy
    # @param filenames [Array<String>] An array of filenames and/or directories containing templates (*required*)
    # @param protected_namespaces [Array<String>] Array of protected Kubernetes namespaces (defaults
    def initialize(namespace:, context:, global_timeout: nil, global_selector: nil, global_selector_as_filter: false, selector: nil,
                   selector_as_filter: false, filenames: [], logger: nil, protected_namespaces: nil, kubeconfig: nil)
      @logger = logger || Krane::FormattedLogger.build(namespace, context)
      @template_sets = TemplateSets.from_dirs_and_files(paths: filenames, logger: @logger, render_erb: false)
      @task_config = TaskConfig.new(context, namespace, logger, kubeconfig)
      @global_timeout = global_timeout
      @global_selector = global_selector
      @global_selector_as_filter = global_selector_as_filter
      @selector = selector
      @selector_as_filter = selector_as_filter
      @protected_namespaces = protected_namespaces
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
    # @param prune [Boolean] Enable deletion of resources that do not appear in the template dir
    #
    # @return [nil]
    def run!(global_verify_result: true, global_prune: true, verify_result: true, prune: true)
      start = Time.now.utc
      logger.reset
    end
  end
end
