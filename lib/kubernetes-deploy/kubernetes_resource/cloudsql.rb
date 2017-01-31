module KubernetesDeploy
  class Cloudsql < KubernetesResource
    TIMEOUT = 30.seconds

    def initialize(name, namespace, file)
      @name, @namespace, @file = name, namespace, file
    end

    def sync
      _, st = run_kubectl("get", type, @name)
      @found = st.success?
      @status = true



      log_status
    end

    def deploy_succeeded?
      cloudsql_proxy_deployment_exists? && mysql_service_exists?
    end

    def deploy_failed?
      !cloudsql_proxy_deployment_exists? || !mysql_service_exists?
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

        if parsed.fetch("status", {}).fetch("availableReplicas", -1) == parsed["replicas"]
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
