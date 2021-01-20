# frozen_string_literal: true
require "krane/kubernetes_resource/pod_set_base"
module Krane
  class DaemonSet < PodSetBase
    TIMEOUT = 5.minutes
    SYNC_DEPENDENCIES = %w(Pod.apps)
    attr_reader :pods

    def sync(cache)
      super
      @pods = exists? ? find_pods(cache) : []
      @nodes = find_nodes(cache) if @nodes.blank?
    end

    def status
      return super unless exists?
      rollout_data.map { |state_replicas, num| "#{num} #{state_replicas}" }.join(", ")
    end

    def deploy_succeeded?
      return false unless exists?
      current_generation == observed_generation &&
        rollout_data["desiredNumberScheduled"].to_i == rollout_data["updatedNumberScheduled"].to_i &&
        relevant_pods_ready?
    end

    def deploy_failed?
      pods.present? && pods.any?(&:deploy_failed?) &&
      observed_generation == current_generation
    end

    def fetch_debug_logs
      most_useful_pod = pods.find(&:deploy_failed?) || pods.find(&:deploy_timed_out?) || pods.first
      most_useful_pod.fetch_debug_logs
    end

    def print_debug_logs?
      pods.present? # the kubectl command times out if no pods exist
    end

    private

    class Node
      attr_reader :name

      class << self
        def kind
          name.demodulize
        end
      end

      def initialize(definition:)
        @name = definition.dig("metadata", "name").to_s
        @definition = definition
      end
    end

    def relevant_pods_ready?
      return true if rollout_data["desiredNumberScheduled"].to_i == rollout_data["numberReady"].to_i # all pods ready
      relevant_node_names = @nodes.map(&:name)
      considered_pods = @pods.select { |p| relevant_node_names.include?(p.node_name) }
      @logger.debug("DaemonSet is reporting #{rollout_data['numberReady']} pods ready." \
        " Considered #{considered_pods.size} pods out of #{@pods.size} for #{@nodes.size} nodes.")
      considered_pods.present? &&
        considered_pods.all?(&:deploy_succeeded?) &&
        rollout_data["numberReady"].to_i >= considered_pods.length
    end

    def find_nodes(cache)
      all_nodes = cache.get_all(Node.kind)
      all_nodes.map { |node_data| Node.new(definition: node_data) }
    end

    def rollout_data
      return { "currentNumberScheduled" => 0 } unless exists?
      @instance_data["status"]
        .slice("updatedNumberScheduled", "desiredNumberScheduled", "numberReady")
    end

    def parent_of_pod?(pod_data)
      return false unless pod_data.dig("metadata", "ownerReferences")

      template_generation = @instance_data.dig("spec", "templateGeneration") ||
        @instance_data.dig("metadata", "annotations", "deprecated.daemonset.template.generation")
      return false unless template_generation.present?

      pod_data["metadata"]["ownerReferences"].any? { |ref| ref["uid"] == @instance_data["metadata"]["uid"] } &&
      pod_data["metadata"]["labels"]["pod-template-generation"].to_i == template_generation.to_i
    end
  end
end
