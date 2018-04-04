# frozen_string_literal: true
require 'kubernetes-deploy/kubernetes_resource/pod_set_base'
module KubernetesDeploy
  class ReplicaSet < PodSetBase
    TIMEOUT = 5.minutes
    attr_reader :pods

    def initialize(namespace:, context:, definition:, logger:, parent: nil, deploy_started_at: nil)
      @parent = parent
      @deploy_started_at = deploy_started_at
      @pods = []
      super(namespace: namespace, context: context, definition: definition, logger: logger)
    end

    SYNC_DEPENDENCIES = %w(Pod)
    def sync(mediator)
      super
      @pods = exists? ? find_pods(mediator) : []
    end

    def status
      return super unless rollout_data.present?
      rollout_data.map { |state_replicas, num| "#{num} #{state_replicas.chop.pluralize(num)}" }.join(", ")
    end

    def deploy_succeeded?
      desired_replicas == rollout_data["availableReplicas"].to_i &&
      desired_replicas == rollout_data["readyReplicas"].to_i
    end

    def deploy_failed?
      pods.present? && pods.all?(&:deploy_failed?)
    end

    def desired_replicas
      return -1 unless exists?
      @instance_data["spec"]["replicas"].to_i
    end

    def ready_replicas
      return -1 unless exists?
      rollout_data['readyReplicas'].to_i
    end

    def available_replicas
      return -1 unless exists?
      rollout_data["availableReplicas"].to_i
    end

    private

    def rollout_data
      return { "replicas" => 0 } unless exists?
      { "replicas" => 0 }.merge(
        @instance_data["status"].slice("replicas", "availableReplicas", "readyReplicas")
      )
    end

    def parent_of_pod?(pod_data)
      return false unless pod_data.dig("metadata", "ownerReferences")
      pod_data["metadata"]["ownerReferences"].any? { |ref| ref["uid"] == @instance_data["metadata"]["uid"] }
    end

    def unmanaged?
      @parent.blank?
    end
  end
end
