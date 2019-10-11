# frozen_string_literal: true
module KubernetesDeploy
  class Secret < KubernetesResource
    TIMEOUT = 30.seconds
    SENSITIVE_TEMPLATE_CONTENT = true
    SERVER_DRY_RUNNABLE = true

    def status
      exists? ? "Available" : "Not Found"
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
