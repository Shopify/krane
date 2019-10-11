# frozen_string_literal: true
module KubernetesDeploy
  class Role < KubernetesResource
    TIMEOUT = 30.seconds

    def status
      exists? ? "Created" : "Not Found"
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
