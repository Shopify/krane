# frozen_string_literal: true
module KubernetesDeploy
  class PodDisruptionBudget < KubernetesResource
    TIMEOUT = 10.seconds

    def status
      exists? ? "Available" : "Unknown"
    end

    def deploy_method
      # Required until https://github.com/kubernetes/kubernetes/issues/45398 changes
      :replace_force
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
