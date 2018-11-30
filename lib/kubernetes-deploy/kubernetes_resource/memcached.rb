# frozen_string_literal: true
module KubernetesDeploy
  class Memcached < KubernetesResource
    TIMEOUT = 5.minutes
    CONFIGMAP_NAME = "memcached-url"

    def sync(cache)
      super
      @deployment = cache.get_instance(Deployment.kind, "memcached-#{@name}")
      @service = cache.get_instance(Service.kind, "memcached-#{@name}")
      @configmap = cache.get_instance(ConfigMap.kind, CONFIGMAP_NAME)
    end

    def status
      deploy_succeeded? ? "Provisioned" : "Unknown"
    end

    def deploy_succeeded?
      deployment_ready? && service_ready? && configmap_ready?
    end

    def deploy_failed?
      false
    end

    private

    def deployment_ready?
      return false unless status = @deployment["status"]
      status.fetch("availableReplicas", -1) == status.fetch("replicas", 0)
    end

    def service_ready?
      return false unless @service.present?
      @service.dig("spec", "clusterIP").present?
    end

    def configmap_ready?
      return false unless @configmap.present?
      @configmap.dig("data", @name).present?
    end
  end
end
