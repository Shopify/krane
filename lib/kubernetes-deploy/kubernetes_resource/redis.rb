module KubernetesDeploy
  class Redis < KubernetesResource
    TIMEOUT = 5.minutes
    UUID_ANNOTATION = "redis.stable.shopify.io/owner_uid".freeze

    def initialize(name, namespace, context, file)
      @name, @namespace, @context, @file = name, namespace, context, file
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
      deployments, st = run_kubectl("get", "deployments", "-o=json")

      if st.success?
        deployment_list = JSON.parse(deployments)
        matching_deployment = detect_resource_by_uuid(deployment_list)

        if matching_deployment \
          && matching_deployment.fetch("status", {}).fetch("availableReplicas", -1) == matching_deployment.fetch("status", {}).fetch("replicas", 0)
          # all redis pods are running
          return true
        end
      end

      false
    end

    def redis_service_exists?
      services, st = run_kubectl("get", "services", "-o=json")

      if st.success?
        service_list = JSON.parse(services)
        matching_service = detect_resource_by_uuid(service_list)

        if matching_service && matching_service.fetch("spec", {}).fetch("clusterIP", "") != ""
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

        if uuid = parsed.fetch("metadata", {}).fetch("annotations", {}).fetch(UUID_ANNOTATION, nil)
          @redis_resource_uuid = uuid
        end
      end
    end

    def detect_resource_by_uuid(resource_list)
      resource_list["items"].detect do |item|
        item.fetch("metadata", {}).fetch("annotations", {}).fetch(UUID_ANNOTATION, nil) == redis_resource_uuid
      end
    end

  end
end
