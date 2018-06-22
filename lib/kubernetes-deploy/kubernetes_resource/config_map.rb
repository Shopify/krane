# frozen_string_literal: true
module KubernetesDeploy
  class ConfigMap < KubernetesResource
    TIMEOUT = 30.seconds

    def status
      exists? ? "Available" : "Unknown"
    end

    def timeout_message
      UNUSUAL_FAILURE_MESSAGE
    end

    private

    def deploy_succeeded?
      exists?
    end
  end
end
