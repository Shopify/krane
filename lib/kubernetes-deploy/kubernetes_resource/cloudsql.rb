# frozen_string_literal: true
module KubernetesDeploy
  class Cloudsql < KubernetesResource
    TIMEOUT = 10.minutes

    SYNC_DEPENDENCIES = %w(Deployment Service)
    def sync(mediator)
      super
      @proxy_deployment = mediator.get_instance(Deployment.kind, "cloudsql-#{cloudsql_resource_uuid}")
      @proxy_service = mediator.get_instance(Service.kind, "cloudsql-#{@name}")
    end

    def status
      if proxy_deployment_ready? && proxy_service_ready?
        "Provisioned"
      else
        "Unknown"
      end
    end

    def deploy_succeeded?
      proxy_deployment_ready? && proxy_service_ready?
    end

    def deploy_failed?
      false
    end

    def deploy_method
      :replace
    end

    private

    def proxy_deployment_ready?
      return false unless status = @proxy_deployment["status"]
      # all cloudsql-proxy pods are running
      status.fetch("availableReplicas", -1) == status.fetch("replicas", 0)
    end

    def proxy_service_ready?
      return false unless @proxy_service.present?
      # the service has an assigned cluster IP and is therefore functioning
      @proxy_service.dig("spec", "clusterIP").present?
    end

    def cloudsql_resource_uuid
      return unless @instance_data
      @instance_data.dig("metadata", "uid")
    end
  end
end
