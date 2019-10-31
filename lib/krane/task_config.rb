# frozen_string_literal: true
module Krane
  class TaskConfig
    attr_reader :context, :namespace

    def initialize(context, namespace, logger = nil)
      @context = context
      @namespace = namespace
      @logger = logger
    end

    def global_kinds
      @global_kinds ||= begin
        cluster_resource_discoverer = ClusterResourceDiscovery.new(task_config: self)
        cluster_resource_discoverer.global_resource_kinds
      end
    end

    def logger
      @logger ||= FormattedLogger.build(@namespace, @context)
    end
  end
end
