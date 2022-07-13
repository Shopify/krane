# frozen_string_literal: true
module Krane
  class Ingress < KubernetesResource
    TIMEOUT = 30.seconds
    GROUPS = ["networking.k8s.io"]

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
