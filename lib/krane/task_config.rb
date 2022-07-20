# frozen_string_literal: true

require 'krane/cluster_resource_discovery'

module Krane
  class TaskConfig
    attr_reader :context, :namespace, :logger, :kubeconfig

    def initialize(context, namespace, logger = nil, kubeconfig = nil)
      @context = context
      @namespace = namespace
      @logger = logger || FormattedLogger.build(@namespace, @context)
      @kubeconfig = kubeconfig || ENV['KUBECONFIG']
    end

    def group_kinds
      @group_kinds ||= cluster_resource_discoverer.fetch_group_kinds
    end

    def kubeclient_builder
      @kubeclient_builder ||= KubeclientBuilder.new(kubeconfig: kubeconfig)
    end

    def cluster_resource_discoverer
      @cluster_resource_discoverer ||= ClusterResourceDiscovery.new(task_config: self)
    end
  end
end
