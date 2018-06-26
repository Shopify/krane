# frozen_string_literal: true
module KubernetesDeploy
  class Job < KubernetesResource
    TIMEOUT = 30.seconds

    def deploy_succeeded?
      # Don't block deploys for long running jobs,
      # Instead report success when there is at least 1 active
      return false unless deploy_started?
      done = (@instance_data.dig("status", "succeeded") || 0) == @instance_data.dig("spec", "completions")
      running = (@instance_data.dig("status", "active") || 0) >= 1
      done || running
    end

    def deploy_failed?
      return false unless deploy_started?
      return false unless @instance_data.dig("spec", "backoffLimit").present?
      (@instance_data.dig("status", "failed") || 0) >= @instance_data.dig("spec", "backoffLimit")
    end

    def timeout_message
      UNUSUAL_FAILURE_MESSAGE
    end
  end
end
