# frozen_string_literal: true
module Krane
  class TaskConfig
    attr_reader :context, :namespace, :logger

    def initialize(context, namespace, logger = nil)
      @context = context
      @namespace = namespace
      @logger = logger || ::Krane::FormattedLogger.build(@namespace, @context)
    end

    def global_kinds
      @global_kinds ||= begin
        cluster_resource_discoverer = ::Krane::ClusterResourceDiscovery.new(task_config: self)
        cluster_resource_discoverer.global_resource_kinds
      end
    end
  end
end
