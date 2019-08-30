# frozen_string_literal: true
module KubernetesDeploy
  class Service < KubernetesResource
    TIMEOUT = 7.minutes

    def sync(cache)
      super
      if exists? && selector.present?
        @related_deployments = cache.get_all(Deployment.kind, selector)
        @related_statefulsets = cache.get_all(StatefulSet.kind, selector)
        @related_pods = cache.get_all(Pod.kind, selector)
      else
        @related_deployments = []
        @related_statefulsets = []
        @related_pods = []
      end
    end

    def status
      if !exists?
        "Not found"
      elsif !requires_endpoints?
        "Doesn't require any endpoints"
      elsif selects_some_pods?
        "Selects at least 1 pod"
      else
        "Selects 0 pods"
      end
    end

    def deploy_succeeded?
      return false unless exists?
      return exists? unless requires_endpoints?
      # We can't use endpoints if we want the service to be able to fail fast when the pods are down
      exposes_zero_replica_workload? || selects_some_pods?
    end

    def deploy_failed?
      false
    end

    def timeout_message
      "This service does not seem to select any pods and this is likely invalid. "\
      "Please confirm the spec.selector is correct and the targeted workload is healthy."
    end

    private

    def exposes_zero_replica_workload?
      return false unless related_replica_count
      related_replica_count == 0
    end

    def requires_endpoints?
      # services of type External don't have endpoints
      return false if external_name_svc?

      # problem counting replicas - by default, assume endpoints are required
      return true if related_replica_count.blank?

      related_replica_count > 0
    end

    def selects_some_pods?
      return false unless selector.present?
      @related_pods.present?
    end

    def selector
      @definition["spec"].fetch("selector", {})
    end

    def related_replica_count
      return 0 unless selector.present?

      if @related_deployments.present?
        @related_deployments.inject(0) { |sum, d| sum + d["spec"]["replicas"].to_i }
      elsif @related_statefulsets.present?
        @related_statefulsets.inject(0) { |sum, d| sum + d["spec"]["replicas"].to_i }
      end
    end

    def external_name_svc?
      @definition["spec"]["type"] == "ExternalName"
    end
  end
end
