module KubernetesDeploy
  class Cloudsql < KubernetesResource
    TIMEOUT = 5.minutes

    def initialize(name, namespace, context, file)
      @name, @namespace, @context, @file = name, namespace, context, file
    end

    def sync
      _, st = run_kubectl("get", type, @name)
      @found = st.success?
      @status = if cloudsql_proxy_deployment_exists? && mysql_service_exists?
        "Provisioned"
      else
        "Unknown"
      end

      log_status
    end

    def deploy_succeeded?
      cloudsql_proxy_deployment_exists? && mysql_service_exists?
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
    def cloudsql_proxy_deployment_exists?
      deployment, st = run_kubectl("get", "deployments", "cloudsql-proxy", "-o=json")

      if st.success?
        parsed = JSON.parse(deployment)

        if parsed.fetch("status", {}).fetch("availableReplicas", -1) == parsed.fetch("status", {}).fetch("replicas", 0)
          # all cloudsql-proxy pods are running
          return true
        end
      end

      false
    end

    def mysql_service_exists?
      service, st = run_kubectl("get", "services", "mysql", "-o=json")

      if st.success?
        parsed = JSON.parse(service)

        if parsed.fetch("spec", {}).fetch("clusterIP", "") != ""
          # the service has an assigned cluster IP and is therefore functioning
          return true
        end
      end

      false
    end

  end
end
