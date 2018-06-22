# frozen_string_literal: true
require 'kubernetes-deploy/kubernetes_resource/pod_set_base'
module KubernetesDeploy
  class DaemonSet < PodSetBase
    TIMEOUT = 5.minutes
    attr_reader :pods

    SYNC_DEPENDENCIES = %w(Pod)
    def sync(mediator)
      super
      @pods = exists? ? find_pods(mediator) : []
    end

    def status
      return super unless exists?
      rollout_data.map { |state_replicas, num| "#{num} #{state_replicas}" }.join(", ")
    end

    def fetch_logs(kubectl)
      return {} unless pods.present?
      most_useful_pod = pods.find { |p| p.deploy_status == "failed" } || pods.find { |p| p.deploy_status == "timed_out" } || pods.first
      most_useful_pod.fetch_logs(kubectl)
    end

    private

    def deploy_succeeded?
      return false unless exists?
      rollout_data["desiredNumberScheduled"].to_i == rollout_data["updatedNumberScheduled"].to_i &&
      rollout_data["desiredNumberScheduled"].to_i == rollout_data["numberReady"].to_i &&
      current_generation == observed_generation
    end

    def deploy_failed?
      pods.present? && pods.any? { |p| p.deploy_status == "failed" }
    end

    def current_generation
      return -1 unless exists? # must be different default than observed_generation
      @instance_data["metadata"]["generation"]
    end

    def observed_generation
      return -2 unless exists?
      @instance_data["status"]["observedGeneration"]
    end

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
