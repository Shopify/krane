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

    def global_kinds
      global_resources.map { |g| g["kind"] }
    end

    def global_resources
      @global_resources ||= begin
        cluster_resource_discoverer = ClusterResourceDiscovery.new(task_config: self)
        cluster_resource_discoverer.fetch_resources(namespaced: false)
      end
    end

    def kubeclient_builder
      @kubeclient_builder ||= KubeclientBuilder.new(kubeconfig: kubeconfig)
    end
  end
end
