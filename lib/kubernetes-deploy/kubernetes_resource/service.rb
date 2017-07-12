# frozen_string_literal: true
module KubernetesDeploy
  class Service < KubernetesResource
    TIMEOUT = 7.minutes

    def sync
      _, _err, st = kubectl.run("get", type, @name)
      @found = st.success?
      @related_deployment_replicas = fetch_related_replica_count
      @status = if @num_pods_selected = fetch_related_pod_count
        "Selects #{@num_pods_selected} #{'pod'.pluralize(@num_pods_selected)}"
      else
        "Failed to count related pods"
      end
    end

    def deploy_succeeded?
      # We can't use endpoints if we want the service to be able to fail fast when the pods are down
      exposes_zero_replica_deployment? || selects_some_pods?
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
      return false unless @related_deployment_replicas
      @related_deployment_replicas == 0
    end

    def selects_some_pods?
      return false unless @num_pods_selected
      @num_pods_selected > 0
    end

    def selector
      @selector ||= @definition["spec"]["selector"].map { |k, v| "#{k}=#{v}" }.join(",")
    end

    def fetch_related_pod_count
      raw_json, _err, st = kubectl.run("get", "pods", "--selector=#{selector}", "--output=json")
      return unless st.success?
      JSON.parse(raw_json)["items"].length
    end

    def fetch_related_replica_count
      raw_json, _err, st = kubectl.run("get", "deployments", "--selector=#{selector}", "--output=json")
      return unless st.success?

      deployments = JSON.parse(raw_json)["items"]
      return unless deployments.length == 1
      deployments.first["spec"]["replicas"].to_i
    end
  end
end
