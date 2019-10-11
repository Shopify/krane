# frozen_string_literal: true
module KubernetesDeploy
  class PodTemplate < KubernetesResource
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
