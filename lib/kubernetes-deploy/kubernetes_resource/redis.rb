# frozen_string_literal: true
module KubernetesDeploy
  class Redis < KubernetesResource
    TIMEOUT = 5.minutes
    UUID_ANNOTATION = "redis.stable.shopify.io/owner_uid"

    def sync
      _, _err, st = kubectl.run("get", type, @name)
      @found = st.success?
      @deployment_exists = redis_deployment_exists?
      @service_exists = redis_service_exists?

      @status = if @deployment_exists && @service_exists
        "Provisioned"
      else
        "Unknown"
      end
    end

    def deploy_succeeded?
      @deployment_exists && @service_exists
    end

    def deploy_failed?
      false
    end

    def tpr?
      true
    end

    def exists?
      @found
    end

    private

    def redis_deployment_exists?
      deployment, _err, st = kubectl.run("get", "deployments", "redis-#{redis_resource_uuid}", "-o=json")

      if st.success?
        parsed = JSON.parse(deployment)

        if parsed.fetch("status", {}).fetch("availableReplicas", -1) == parsed.fetch("status", {}).fetch("replicas", 0)
          # all redis pods are running
          return true
        end
      end

      false
    end

    def redis_service_exists?
      service, _err, st = kubectl.run("get", "services", "redis-#{redis_resource_uuid}", "-o=json")

      if st.success?
        parsed = JSON.parse(service)

        if parsed.fetch("spec", {}).fetch("clusterIP", "") != ""
          return true
        end
      end

      false
    end

    def redis_resource_uuid
      return @redis_resource_uuid if defined?(@redis_resource_uuid) && @redis_resource_uuid

      redis, _err, st = kubectl.run("get", "redises", @name, "-o=json")
      if st.success?
        parsed = JSON.parse(redis)

        @redis_resource_uuid = parsed.fetch("metadata", {}).fetch("uid", nil)
      end
    end
  end
end
