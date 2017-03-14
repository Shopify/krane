# frozen_string_literal: true
module KubernetesDeploy
  class Redis < KubernetesResource
    TIMEOUT = 5.minutes
    UUID_ANNOTATION = "redis.stable.shopify.io/owner_uid"

    def initialize(name, namespace, context, file)
      @name = name
      @namespace = namespace
      @context = context
      @file = file
    end

    def sync
      _, st = run_kubectl("get", type, @name)
      @found = st.success?
      @status = if redis_deployment_exists? && redis_service_exists?
        "Provisioned"
      else
        "Unknown"
      end

      log_status
    end

    def deploy_succeeded?
      redis_deployment_exists? && redis_service_exists?
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
      deployment, st = run_kubectl("get", "deployments", "redis-#{redis_resource_uuid}", "-o=json")

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
      service, st = run_kubectl("get", "services", "redis-#{redis_resource_uuid}", "-o=json")

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

      redis, st = run_kubectl("get", "redises", @name, "-o=json")
      if st.success?
        parsed = JSON.parse(redis)

        @redis_resource_uuid = parsed.fetch("metadata", {}).fetch("uid", nil)
      end
    end
  end
end
