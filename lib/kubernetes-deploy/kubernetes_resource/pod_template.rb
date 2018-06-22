# frozen_string_literal: true
module KubernetesDeploy
  class PodTemplate < KubernetesResource
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
