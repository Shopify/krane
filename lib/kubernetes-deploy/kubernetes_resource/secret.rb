# frozen_string_literal: true
module KubernetesDeploy
  class Secret < KubernetesResource
    TIMEOUT = 30.seconds
    KUBECTL_OUTPUT_IS_SENSITIVE = true

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
