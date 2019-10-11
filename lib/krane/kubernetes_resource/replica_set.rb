# frozen_string_literal: true
require 'kubernetes-deploy/kubernetes_resource/pod_set_base'

module KubernetesDeploy
  class ReplicaSet < PodSetBase
    TIMEOUT = 5.minutes
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
      @pods = fetch_pods_if_needed(cache) || []
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

    def fetch_pods_if_needed(cache)
      # If the ReplicaSet doesn't exist, its pods won't either
      return unless exists?
      # If the status hasn't been updated yet, we're not going to make a determination anyway
      return if stale_status?
      # If we don't want any pods at all, we don't need to look for them
      return if desired_replicas == 0
      # We only need to fetch pods so that deploy_failed? can check that they aren't ALL bad.
      # If we can already tell some pods are ok from the RS data, don't bother fetching them (which can be expensive)
      # Lower numbers here make us more susceptible to being fooled by replicas without probes briefly appearing ready
      return if ready_replicas > 1

      find_pods(cache)
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
