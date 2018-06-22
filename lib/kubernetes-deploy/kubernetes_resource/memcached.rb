# frozen_string_literal: true
module KubernetesDeploy
  class Memcached < KubernetesResource
    TIMEOUT = 5.minutes
    CONFIGMAP_NAME = "memcached-url"

    SYNC_DEPENDENCIES = %w(Deployment Service ConfigMap)
    def sync(mediator)
      super
      @deployment = mediator.get_instance(Deployment.kind, "memcached-#{@name}")
      @service = mediator.get_instance(Service.kind, "memcached-#{@name}")
      @configmap = mediator.get_instance(ConfigMap.kind, CONFIGMAP_NAME)
    end

    def status
      deploy_succeeded? ? "Provisioned" : "Unknown"
    end

    def deploy_method
      :replace
    end

    private

    def deploy_succeeded?
      deployment_ready? && service_ready? && configmap_ready?
    end

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
