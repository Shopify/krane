# frozen_string_literal: true
require 'krane/common'
require 'krane/cluster_resource_discovery'

module Krane
  class WatchTask
    include TemplateReporting
    delegate :namespace, :context, :logger, to: :@task_config

    def initialize(namespace:, context:, filenames: [], max_watch_seconds: nil)
      template_paths = filenames.map { |path| File.expand_path(path) }

      @task_config = TaskConfig.new(context, namespace)
      @template_sets = TemplateSets.from_dirs_and_files(paths: template_paths, logger: @task_config.logger)
      @max_watch_seconds = max_watch_seconds
    end

    def run(*args)
      run!(*args)
      true
    rescue FatalDeploymentError
      false
    end

    def run!(*_args)
      resources = discover_resources
      watcher = ResourceWatcher.new(
        resources: resources,
        task_config: @task_config,
        operation_name: 'sync',
        timeout: @max_watch_seconds,
      )
      watcher.run
    end

    private

    def discover_resources
      logger.info("Discovering resources:")
      resources = []
      crds_by_kind = cluster_resource_discoverer.crds.map { |crd| [crd.name, crd] }.to_h
      @template_sets.with_resource_definitions do |definition|
        crd = crds_by_kind[definition["kind"]]&.first
        resource = KubernetesResource.build(namespace: namespace, context: context, logger: logger, definition: definition,
          crd: crd, statsd_tags: statsd_tags)
        resources << resource
        logger.info("  - #{resource.id}")
      end

      resources.sort
    rescue InvalidTemplateError => e
      record_invalid_template(logger: logger, err: e.message, filename: e.filename, content: e.content)
      raise FatalDeploymentError, "Failed to parse template"
    end

    def statsd_tags
      %W(context:#{context} namespace:#{namespace})
    end

    def cluster_resource_discoverer
      @cluster_resource_discoverer ||= ClusterResourceDiscovery.new(task_config: @task_config)
    end
  end
end
