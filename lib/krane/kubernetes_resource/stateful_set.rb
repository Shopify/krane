# frozen_string_literal: true
require 'krane/kubernetes_resource/pod_set_base'
module Krane
  class StatefulSet < PodSetBase
    TIMEOUT = 10.minutes
    ONDELETE = 'OnDelete'
    SYNC_DEPENDENCIES = %w(Pod)
    REQUIRED_ROLLOUT_TYPES = %w(full).freeze
    attr_reader :pods

    def sync(cache)
      super
      @pods = exists? ? find_pods(cache) : []
    end

    def status
      return super unless @instance_data["status"].present?
      rollout_data = @instance_data["status"].slice("replicas", "readyReplicas", "currentReplicas")
      rollout_data.map { |state_replicas, num| "#{num} #{state_replicas.chop.pluralize(num)}" }.join(", ")
    end

    def deploy_succeeded?
      success = observed_generation == current_generation

      if update_strategy == ONDELETE && required_rollout != "full"
        unless @success_assumption_warning_shown
          @logger.warn("WARNING: Your StatefulSet's updateStrategy is set to #{update_strategy}, "\
                       "which means updates will not be applied until its pods are deleted.")
          @success_assumption_warning_shown = true
        end
      else
        success &= desired_replicas == status_data['readyReplicas'].to_i
        success &= desired_replicas == status_data['updatedReplicas'].to_i
      end

      success
    end

    def deploy_failed?
      return false if update_strategy == ONDELETE && required_rollout != 'full'
      pods.present? && pods.any?(&:deploy_failed?) &&
      observed_generation == current_generation
    end

    private

    def update_strategy
      if exists?
        @instance_data['spec']['updateStrategy']['type']
      else
        'Unknown'
      end
    end

    def status_data
      return { 'readyReplicas' => '-1', 'currentReplicas' => '-2' } unless exists?
      @instance_data["status"]
    end

    def desired_replicas
      return -1 unless exists?
      @instance_data["spec"]["replicas"].to_i
    end

    def parent_of_pod?(pod_data)
      return false unless pod_data.dig("metadata", "ownerReferences")
      pod_data["metadata"]["ownerReferences"].any? { |ref| ref["uid"] == @instance_data["metadata"]["uid"] } &&
      @instance_data["status"]["updateRevision"] == pod_data["metadata"]["labels"]["controller-revision-hash"]
    end

    def required_rollout
      krane_annotation_value("required-rollout") || nil
    end
  end
end
