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
      @global_kinds ||= begin
        fetch_resources.map { |g| g["kind"] }
      end
    end

    def global_group_kinds
      @global_group_kinds ||= begin
        fetch_resources.map { |g| Krane.group_kind(g["apigroup"], g["kind"]) }
      end
    end

    def group_kind_to_kind(group_kind)
      hashy = fetch_resources.find{ |x| Krane.group_kind(x["apigroup"], x["kind"]) == group_kind }

      hashy["kind"]
    end

    def kubeclient_builder
      @kubeclient_builder ||= KubeclientBuilder.new(kubeconfig: kubeconfig)
    end

    def cluster_resource_discoverer
      @cluster_resource_discoverer ||= ClusterResourceDiscovery.new(task_config: self)
    end

    def fetch_resources
      @fetch_resources ||= cluster_resource_discoverer.fetch_resources(namespaced: false)
    end
  end
end
