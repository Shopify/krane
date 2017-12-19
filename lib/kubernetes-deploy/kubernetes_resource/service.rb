# frozen_string_literal: true
module KubernetesDeploy
  class Service < KubernetesResource
    TIMEOUT = 7.minutes

    def sync
      _, _err, st = kubectl.run("get", type, @name)
      @found = st.success?
      @related_deployment_replicas = fetch_related_replica_count
      @num_pods_selected = fetch_related_pod_count
    end

    def status
      if !requires_endpoints?
        "Doesn't require any endpoint"
      elsif @num_pods_selected.blank?
        "Failed to count related pods"
      elsif selects_some_pods?
        "Selects at least 1 pod"
      else
        "Selects 0 pods"
      end
    end

    def deploy_succeeded?
      return exists? unless requires_endpoints?
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

    def requires_endpoints?
      # service of type External don't have endpoints
      return false if external_name_svc?

      # problem counting replicas - by default, assume endpoints are required
      return true if @related_deployment_replicas.blank?

      @related_deployment_replicas > 0
    end

    def selects_some_pods?
      return false unless @num_pods_selected
      @num_pods_selected > 0
    end

    def selector
      @selector ||= @definition["spec"].fetch("selector", []).map { |k, v| "#{k}=#{v}" }.join(",")
    end

    def fetch_related_pod_count
      return 0 unless selector.present?
      raw_json, _err, st = kubectl.run("get", "pods", "--selector=#{selector}", "--output=json")
      return unless st.success?
      JSON.parse(raw_json)["items"].length
    end

    def fetch_related_replica_count
      return 0 unless selector.present?
      raw_json, _err, st = kubectl.run("get", "deployments", "--selector=#{selector}", "--output=json")
      return unless st.success?

      deployments = JSON.parse(raw_json)["items"]
      return unless deployments.length == 1
      deployments.first["spec"]["replicas"].to_i
    end

    def external_name_svc?
      @definition["spec"]["type"] == "ExternalName"
    end
  end
end
