# frozen_string_literal: true
module KubernetesDeploy
  class HorizontalPodAutoscaler < KubernetesResource
    TIMEOUT = 3.minutes
    RECOVERABLE_CONDITIONS = %w(ScalingDisabled FailedGet)

    def deploy_succeeded?
      scaling_active_condition["status"] == "True"
    end

    def deploy_failed?
      return false unless exists?
      recoverable = RECOVERABLE_CONDITIONS.any? { |c| scaling_active_condition.fetch("reason", "").start_with?(c) }
      scaling_active_condition["status"] == "False" && !recoverable
    end

    def kubectl_resource_type
      'hpa.v2beta1.autoscaling'
    end

    def status
      if !exists?
        super
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
      condition = scaling_active_condition.presence || able_to_scale_condition.presence || {}
      condition['message']
    end

    def timeout_message
      failure_message.presence || super
    end

    private

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
