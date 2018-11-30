# frozen_string_literal: true
require 'kubernetes-deploy/kubernetes_resource/pod_set_base'
module KubernetesDeploy
  class DaemonSet < PodSetBase
    TIMEOUT = 5.minutes
    attr_reader :pods

    def sync(cache)
      super
      @pods = exists? ? find_pods(cache) : []
    end

    def status
      return super unless exists?
      rollout_data.map { |state_replicas, num| "#{num} #{state_replicas}" }.join(", ")
    end

    def deploy_succeeded?
      return false unless exists?
      rollout_data["desiredNumberScheduled"].to_i == rollout_data["updatedNumberScheduled"].to_i &&
      rollout_data["desiredNumberScheduled"].to_i == rollout_data["numberReady"].to_i &&
      current_generation == observed_generation
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

    def rollout_data
      return { "currentNumberScheduled" => 0 } unless exists?
      @instance_data["status"]
        .slice("updatedNumberScheduled", "desiredNumberScheduled", "numberReady")
    end

    def parent_of_pod?(pod_data)
      return false unless pod_data.dig("metadata", "ownerReferences")
      pod_data["metadata"]["ownerReferences"].any? { |ref| ref["uid"] == @instance_data["metadata"]["uid"] } &&
      pod_data["metadata"]["labels"]["pod-template-generation"].to_i ==
        @instance_data["spec"]["templateGeneration"].to_i
    end
  end
end
