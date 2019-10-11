# frozen_string_literal: true
module KubernetesDeploy
  class Ingress < KubernetesResource
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
  end
end
