# frozen_string_literal: true
require 'kubernetes-deploy/kubernetes_resource/pod_set_base'
module KubernetesDeploy
  class DaemonSet < PodSetBase
    TIMEOUT = 5.minutes
    attr_reader :pods

    def sync
      raw_json, _err, st = kubectl.run("get", type, @name, "--output=json")
      @found = st.success?

      if @found
        daemonset_data = JSON.parse(raw_json)
        @current_generation = daemonset_data["metadata"]["generation"]
        @observed_generation = daemonset_data["status"]["observedGeneration"]
        @rollout_data = daemonset_data["status"]
          .slice("currentNumberScheduled", "desiredNumberScheduled", "numberReady")
        @status = @rollout_data.map { |state_replicas, num| "#{num} #{state_replicas}" }.join(", ")
        @pods = find_pods(daemonset_data)
      else # reset
        @rollout_data = { "currentNumberScheduled" => 0 }
        @current_generation = 1 # to make sure the current and observed generations are different
        @observed_generation = 0
        @status = nil
        @pods = []
      end
    end

    def deploy_succeeded?
      @rollout_data["desiredNumberScheduled"].to_i == @rollout_data["currentNumberScheduled"].to_i &&
      @rollout_data["desiredNumberScheduled"].to_i == @rollout_data["numberReady"].to_i &&
      @current_generation == @observed_generation
    end

    def deploy_failed?
      pods.present? && pods.any?(&:deploy_failed?)
    end

    def fetch_logs
      most_useful_pod = @pods.find(&:deploy_failed?) || @pods.find(&:deploy_timed_out?) || @pods.first
      most_useful_pod.fetch_logs
    end

    def exists?
      @found
    end

    private

    def parent_of_pod?(set_data, pod_data)
      return false unless pod_data.dig("metadata", "ownerReferences")
      pod_data["metadata"]["ownerReferences"].any? { |ref| ref["uid"] == set_data["metadata"]["uid"] } &&
      pod_data["metadata"]["labels"]["pod-template-generation"].to_i == set_data["spec"]["templateGeneration"].to_i
    end
  end
end
