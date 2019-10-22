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
      @global_kinds ||= cluster_resource_discoverer.global_resource_kinds
    end

    def logger
      @logger ||= Krane::FormattedLogger.build(@namespace, @context)
    end

    private

    def cluster_resource_discoverer
      @cluster_resource_discoverer ||= Krane::ClusterResourceDiscovery.new(task_config: self)
    end

    def kubectl
      @kubectl ||= Krane::Kubectl.new(task_config: self, log_failure_by_default: true)
    end
  end
end
