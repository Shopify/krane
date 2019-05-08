# frozen_string_literal: true

require 'kubernetes-deploy/resource_watcher'
require 'kubernetes-deploy/renderer'
require 'kubernetes-deploy/cluster_resource_discovery'
require 'kubernetes-deploy/template_discovery'

module KubernetesDeploy
  class WatchOnlyTask
    def initialize(namespace:, context:, template_dir:, bindings:, logger:, sha: '')
      @namespace = namespace
      @context = context
      @template_dir = template_dir
      @logger = logger
      @sha = sha
      @bindings = bindings
    end

    def run
      @logger.phase_heading("Initializing task")
      resources = resources_from_templates
      # should add secrets from ejson or log that they are being skipped

      @logger.phase_heading("Watch")
      failed_resources = watch_resources(resources)
      @logger.print_summary(:failure) if failed_resources > 0
      @logger.print_summary(:success) if failed_resources == 0
      raise FatalDeploymentError unless failed_resources == 0
    end

    private

    def watch_resources(resources)
      watcher = ResourceWatcher.new(
        resources: resources,
        logger: @logger,
        context: @context,
        namespace: @namespace
      )
      watcher.run
    end

    def resources_from_templates
      renderer = Renderer.new(current_sha: @sha, template_dir: @template_dir, logger: @logger, bindings: @bindings)
      discovery = TemplateDiscovery.new(namespace: @namespace, context: @context, logger: @logger)
      resources = discovery.resources(@template_dir, renderer, cluster_resource_discoverer.crds.group_by(&:kind))
      resources.reject! do |r|
        if r.type == "Pod"
          basename = r.name.split("-")[0..-3].join("-")
          @logger.warn("Not simulating watch for #{basename} pod because its real ID cannot be determined")
        end
      end

      @logger.info("Will look for the following resources in #{@context}/#{@namespace}:")
      resources.each do |r|
        r.deploy_started_at = 5.minutes.ago # arbitrary time in the past
        @logger.info("  - #{r.id}")
      end
      resources
    end

    def cluster_resource_discoverer
      @cluster_resource_discoverer ||= ClusterResourceDiscovery.new(
        namespace: @namespace,
        context: @context,
        logger: @logger,
        namespace_tags: @namespace_tags
      )
    end
  end
end
