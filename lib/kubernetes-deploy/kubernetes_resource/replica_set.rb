# frozen_string_literal: true
require 'kubernetes-deploy/kubernetes_resource/pod_set_base'
module KubernetesDeploy
  class ReplicaSet < PodSetBase
    TIMEOUT = 5.minutes
    attr_reader :desired_replicas, :pods

    def initialize(namespace:, context:, definition:, logger:, parent: nil, deploy_started_at: nil)
      @parent = parent
      @deploy_started_at = deploy_started_at
      @rollout_data = { "replicas" => 0 }
      @desired_replicas = -1
      @pods = []
      super(namespace: namespace, context: context, definition: definition, logger: logger)
    end

    def sync(rs_data = nil)
      if rs_data.blank?
        raw_json, _err, st = kubectl.run("get", type, @name, "--output=json")
        rs_data = JSON.parse(raw_json) if st.success?
      end

      if rs_data.present?
        @found = true
        @desired_replicas = rs_data["spec"]["replicas"].to_i
        @rollout_data = { "replicas" => 0 }.merge(
          rs_data["status"].slice("replicas", "availableReplicas", "readyReplicas")
        )
        @status = @rollout_data.map { |state_replicas, num| "#{num} #{state_replicas.chop.pluralize(num)}" }.join(", ")
        @pods = find_pods(rs_data)
      else # reset
        @found = false
        @rollout_data = { "replicas" => 0 }
        @status = nil
        @pods = []
        @desired_replicas = -1
      end
    end

    def deploy_succeeded?
      @desired_replicas == @rollout_data["availableReplicas"].to_i &&
      @desired_replicas == @rollout_data["readyReplicas"].to_i
    end

    def deploy_failed?
      pods.present? && pods.all?(&:deploy_failed?)
    end

    def exists?
      @found
    end

    private

    def parent_of_pod?(set_data, pod_data)
      return false unless pod_data.dig("metadata", "ownerReferences")
      pod_data["metadata"]["ownerReferences"].any? { |ref| ref["uid"] == set_data["metadata"]["uid"] }
    end

    def unmanaged?
      @parent.blank?
    end
  end
end
