# frozen_string_literal: true
module KubernetesDeploy
  class Cloudsql < KubernetesResource
    TIMEOUT = 10.minutes

    def sync
      _, _err, st = kubectl.run("get", type, @name)
      @found = st.success?
      @deployment_exists = cloudsql_proxy_deployment_exists?
      @service_exists = mysql_service_exists?
      @status = if @deployment_exists && @service_exists
        "Provisioned"
      else
        "Unknown"
      end
    end

    def deploy_succeeded?
      @service_exists && @deployment_exists
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
      deployment, _err, st = kubectl.run("get", "deployments", "cloudsql-proxy", "-o=json")

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
      service, _err, st = kubectl.run("get", "services", "mysql", "-o=json")

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
