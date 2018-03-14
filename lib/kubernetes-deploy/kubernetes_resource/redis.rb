# frozen_string_literal: true
module KubernetesDeploy
  class Redis < KubernetesResource
    TIMEOUT = 5.minutes
    UUID_ANNOTATION = "redis.stable.shopify.io/owner_uid"

    SYNC_DEPENDENCIES = %w(Deployment Service)
    def sync(mediator)
      super
      @deployment = mediator.get_instance(Deployment.kind, "redis-#{redis_resource_uuid}")
      @service = mediator.get_instance(Service.kind, "redis-#{redis_resource_uuid}")
    end

    def status
      if deployment_ready? && service_ready?
        "Provisioned"
      else
        "Unknown"
      end
    end

    def deploy_succeeded?
      deployment_ready? && service_ready?
    end

    def deploy_failed?
      false
    end

    def deploy_method
      :replace
    end

    private

    def deployment_ready?
      return false unless status = @deployment["status"]
      # all redis pods are running
      status.fetch("availableReplicas", -1) == status.fetch("replicas", 0)
    end

    def service_ready?
      return false unless @service.present?
      # the service has an assigned cluster IP and is therefore functioning
      @service.dig("spec", "clusterIP").present?
    end

    def redis_resource_uuid
      return unless @instance_data.present?
      @instance_data.dig("metadata", "uid")
    end
  end
end
