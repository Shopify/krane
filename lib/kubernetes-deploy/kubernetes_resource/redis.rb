# frozen_string_literal: true
module KubernetesDeploy
  class Redis < KubernetesResource
    TIMEOUT = 5.minutes
    UUID_ANNOTATION = "redis.stable.shopify.io/owner_uid"

    def sync(cache)
      super

      @deployment = cache.get_instance(Deployment.kind, name)
      @deployment = cache.get_instance(Deployment.kind, deprecated_name) if @deployment.empty?

      @service = cache.get_instance(Service.kind, name)
      @service = cache.get_instance(Service.kind, deprecated_name) if @service.empty?
    end

    def status
      deploy_succeeded? ? "Provisioned" : "Unknown"
    end

    def deploy_succeeded?
      deployment_ready? && service_ready?
    end

    def deploy_failed?
      false
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

    def name
      @definition.dig('metadata', 'name')
    end

    def deprecated_name
      "redis-#{redis_resource_uuid}"
    end

    def redis_resource_uuid
      return unless @instance_data.present?
      @instance_data.dig("metadata", "uid")
    end
  end
end
