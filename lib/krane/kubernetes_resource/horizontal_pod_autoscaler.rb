# frozen_string_literal: true
module Krane
  class HorizontalPodAutoscaler < KubernetesResource
    TIMEOUT = 3.minutes
    RECOVERABLE_CONDITION_PREFIX = "FailedGet"
    TIMEOUT_MESSAGE_DIFFERENT_GENERATIONS = <<~MSG
      This resource's status could not be used to determine rollout success because it is not up-to-date
      (.metadata.generation != .status.observedGeneration).
    MSG

    def deploy_succeeded?
      return false if stale_status?
      scaling_active_condition["status"] == "True" || scaling_disabled?
    end

    def deploy_failed?
      return false if stale_status?
      return false if scaling_disabled?
      scaling_active_condition["status"] == "False" &&
      !scaling_active_condition.fetch("reason", "").start_with?(RECOVERABLE_CONDITION_PREFIX)
    end

    def kubectl_resource_type
      'hpa.v2.autoscaling'
    end

    def status
      if !exists?
        super
      elsif stale_status?
        "Unknown"
      elsif scaling_disabled?
        "ScalingDisabled"
      elsif deploy_succeeded?
        "Configured"
      elsif scaling_active_condition.present? || able_to_scale_condition.present?
        condition = scaling_active_condition.presence || able_to_scale_condition
        condition['reason']
      else
        "Unknown"
      end
    end

    def failure_message
      return if stale_status?
      condition = scaling_active_condition.presence || able_to_scale_condition.presence || {}
      condition['message']
    end

    def timeout_message
      if exists? && stale_status?
        TIMEOUT_MESSAGE_DIFFERENT_GENERATIONS
      else
        failure_message.presence || super
      end
    end

    private

    def stale_status?
      return true unless exists?
      return false if observed_generation.nil? || current_generation.nil?

      observed_generation != current_generation
    end

    def scaling_disabled?
      scaling_active_condition["status"] == "False" &&
      scaling_active_condition["reason"] == "ScalingDisabled"
    end

    def conditions
      @instance_data.dig("status", "conditions") || []
    end

    def able_to_scale_condition
      conditions.detect { |c| c["type"] == "AbleToScale" } || {}
    end

    def scaling_active_condition
      conditions.detect { |c| c["type"] == "ScalingActive" } || {}
    end
  end
end
