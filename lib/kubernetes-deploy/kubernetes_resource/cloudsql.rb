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
      deployments, st = run_kubectl("get", "deployments", "--selector", "name=cloudsql-proxy", "--namespace=#{@namespace}", "-o=json")
      if st.success?
        deployment_list = JSON.parse(deployments)
        cloudsql_proxy = deployment_list["items"].first

        if cloudsql_proxy.fetch("status", {}).fetch("availableReplicas", -1) == cloudsql_proxy["replicas"]
          # all cloudsql-proxy pods are running
          return true
        end
      end

      false
    end

    def mysql_service_exists?
      services, st = run_kubectl("get", "services", "--selector", "name=mysql", "--namespace=#{@namespace}", "-o=json")
      if st.success?
        services_list = JSON.parse(services)

        if .any? { |s| s.fetch("spec", {}).fetch("clusterIP", "") != "" }
          # the service has an assigned cluster IP and is therefore functioning
          return true
        end
      end

      false
    end

  end
end
