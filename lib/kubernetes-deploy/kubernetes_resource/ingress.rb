# frozen_string_literal: true
module KubernetesDeploy
  class Ingress < KubernetesResource
    TIMEOUT = 30.seconds

    def status
      if !exists?
        "Not Found"
      elsif !published?
        "LoadBalancer IP address is not provisioned yet"
      else
        "Created"
      end
    end

    def deploy_succeeded?
      return false unless exists?
      return published?
    end

    def deploy_failed?
      false
    end

    private

    def published?
      @instance_data.dig('status', 'loadBalancer', 'ingress').present?
    end
  end
end
