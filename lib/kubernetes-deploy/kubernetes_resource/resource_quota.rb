# frozen_string_literal: true
module KubernetesDeploy
  class ResourceQuota < KubernetesResource
    TIMEOUT = 30.seconds

    def status
      exists? ? "In effect" : "Unknown"
    end

    def timeout_message
      UNUSUAL_FAILURE_MESSAGE
    end

    private

    def deploy_succeeded?
      @instance_data.dig("spec", "hard") == @instance_data.dig("status", "hard")
    end
  end
end
