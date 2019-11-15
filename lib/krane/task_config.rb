# frozen_string_literal: true

require 'krane/cluster_resource_discovery'

module Krane
  class TaskConfig
    attr_reader :context, :namespace, :logger

    def initialize(context, namespace, logger = nil)
      @context = context
      @namespace = namespace
      @logger = logger || FormattedLogger.build(@namespace, @context)
    end

    def global_kinds
      @global_kinds ||= begin
        cluster_resource_discoverer = ClusterResourceDiscovery.new(task_config: self)
        cluster_resource_discoverer.fetch_resources(namespaced: false).map { |g| g["kind"] }
      end
    end
  end
end
