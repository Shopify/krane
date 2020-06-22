# frozen_string_literal: true
require 'krane/kubernetes_resource/pod_set_base'

module Krane
  class ReplicaSet < PodSetBase
    TIMEOUT = 5.minutes
    SYNC_DEPENDENCIES = %w(Pod)
    attr_reader :pods

    def initialize(namespace:, context:, definition:, logger:, statsd_tags: nil,
      parent: nil, deploy_started_at: nil)
      @parent = parent
      @deploy_started_at = deploy_started_at
      @pods = []
      super(namespace: namespace, context: context, definition: definition,
            logger: logger, statsd_tags: statsd_tags)
    end

    def sync(cache)
      super
      @pods = exists? ? find_pods(cache) : []
    end

    def status
      return super unless rollout_data.present?
      rollout_data.map { |state_replicas, num| "#{num} #{state_replicas.chop.pluralize(num)}" }.join(", ")
    end

    def deploy_succeeded?
      return false if stale_status?
      desired_replicas == rollout_data["availableReplicas"].to_i &&
      desired_replicas == rollout_data["readyReplicas"].to_i
    end

    def deploy_failed?
      pods.present? &&
      pods.all?(&:deploy_failed?) &&
      !stale_status?
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

    def stale_status?
      observed_generation != current_generation
    end

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
