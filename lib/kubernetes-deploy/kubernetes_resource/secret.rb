# frozen_string_literal: true
module KubernetesDeploy
  class Secret < KubernetesResource
    TIMEOUT = 10.seconds

    def status
      exists? ? "Available" : "Unknown"
    end

    def deploy_succeeded?
      exists?
    end

    def deploy_failed?
      false
    end

    def timeout_message
      UNUSUAL_FAILURE_MESSAGE
    end
  end
end
