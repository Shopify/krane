# frozen_string_literal: true
module KubernetesDeploy
  class Ingress < KubernetesResource
    TIMEOUT = 30.seconds

    def status
      exists? ? "Created" : "Unknown"
    end

    private

    def deploy_succeeded?
      exists?
    end
  end
end
