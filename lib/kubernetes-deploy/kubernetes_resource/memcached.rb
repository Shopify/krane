# frozen_string_literal: true
module KubernetesDeploy
  class Memcached < KubernetesResource
    TIMEOUT = 5.minutes
    SECRET_NAME = "memcached-url"

    def sync
      _, _err, st = kubectl.run("get", type, @name)
      @found = st.success?
      @deployment_exists = memcached_deployment_exists?
      @service_exists = memcached_service_exists?
      @secret_exists = memcached_secret_exists?

      @status = if @deployment_exists && @service_exists && @secret_exists
        "Provisioned"
      else
        "Unknown"
      end
    end

    def deploy_succeeded?
      @deployment_exists && @service_exists && @secret_exists
    end

    def deploy_failed?
      false
    end

    def exists?
      @found
    end

    private

    def memcached_deployment_exists?
      deployment, _err, st = kubectl.run("get", "deployments", @name, "-o=json")
      return false unless st.success?
      parsed = JSON.parse(deployment)
      parsed.fetch("status", {}).fetch("availableReplicas", -1) == parsed.fetch("status", {}).fetch("replicas", 0)
    end

    def memcached_service_exists?
      service, _err, st = kubectl.run("get", "services", @name, "-o=json")
      return false unless st.success?
      parsed = JSON.parse(service)
      parsed.dig("spec", "clusterIP").present?
    end

    def memcached_secret_exists?
      secret, _err, st = kubectl.run("get", "secrets", SECRET_NAME, "-o=json")
      return false unless st.success?
      parsed = JSON.parse(secret)
      parsed.dig("data", @name).present?
    end
  end
end
