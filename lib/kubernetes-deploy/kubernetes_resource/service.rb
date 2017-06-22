# frozen_string_literal: true
module KubernetesDeploy
  class Service < KubernetesResource
    TIMEOUT = 7.minutes

    def sync
      _, _err, st = kubectl.run("get", type, @name)
      @found = st.success?
      @related_deployment_replicas = fetch_related_replica_count
      @num_pods_selected = fetch_related_pod_count
      @status = "Selects #{@num_pods_selected} #{'pod'.pluralize(@num_pods_selected)}"
    end

    def deploy_succeeded?
      # We can't use endpoints if we want the service to be able to fail fast when the pods are down
      @num_pods_selected > 0 || exposes_zero_replica_deployment?
    end

    def deploy_failed?
      false
    end

    def timeout_message
      "This service does not seem to select any pods. This means its spec.selector is probably incorrect."
    end

    def exists?
      @found
    end

    private

    def exposes_zero_replica_deployment?
      @related_deployment_replicas == 0
    end

    def selector
      @selector ||= @definition["spec"]["selector"].map { |k, v| "#{k}=#{v}" }.join(",")
    end

    def fetch_related_pod_count
      raw_json, _err, st = kubectl.run("get", "pods", "--selector=#{selector}", "--output=json")
      return 0 unless st.success?
      JSON.parse(raw_json)["items"].length
    end

    def fetch_related_replica_count
      raw_json, _err, st = kubectl.run("get", "deployments", "--selector=#{selector}", "--output=json")
      return 1 unless st.success?

      deployments = JSON.parse(raw_json)["items"]
      return 1 unless deployments.length == 1
      deployments.first["spec"]["replicas"].to_i
    end
  end
end
