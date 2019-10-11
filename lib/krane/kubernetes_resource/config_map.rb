# frozen_string_literal: true
module KubernetesDeploy
  class ConfigMap < KubernetesResource
    TIMEOUT = 30.seconds

    def deploy_succeeded?
      exists?
    end

    def status
      exists? ? "Available" : "Not Found"
    end

    def deploy_failed?
      false
    end

    def timeout_message
      UNUSUAL_FAILURE_MESSAGE
    end
  end
end
