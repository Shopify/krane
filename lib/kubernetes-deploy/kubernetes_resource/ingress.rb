# frozen_string_literal: true
module KubernetesDeploy
  class Ingress < KubernetesResource
    TIMEOUT = 30.seconds
    PRUNABLE = true

    def status
      exists? ? "Created" : "Unknown"
    end

    def deploy_succeeded?
      exists?
    end

    def deploy_failed?
      false
    end
  end
end
