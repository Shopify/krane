# frozen_string_literal: true
module KubernetesDeploy
  class Service < KubernetesResource
    TIMEOUT = 7.minutes

    SYNC_DEPENDENCIES = %w(Pod Deployment)
    def sync(mediator)
      super
      @related_deployments = mediator.get_all(Deployment.kind, selector)
      @related_pods = mediator.get_all(Pod.kind, selector)
    end

    def status
      if !requires_endpoints?
        "Doesn't require any endpoints"
      elsif @related_pods.present?
        "Selects at least 1 pod"
      else
        "Selects 0 pods"
      end
    end

    def deploy_succeeded?
      return exists? unless requires_endpoints?
      # We can't use endpoints if we want the service to be able to fail fast when the pods are down
      exposes_zero_replica_deployment? || related_replica_count > 0
    end

    def deploy_failed?
      false
    end

    def timeout_message
      "This service does not seem to select any pods. This means its spec.selector is probably incorrect."
    end

    private

    def exposes_zero_replica_deployment?
      return false unless related_replica_count
      related_replica_count == 0
    end

    def requires_endpoints?
      # service of type External don't have endpoints
      return false if external_name_svc?

      # problem counting replicas - by default, assume endpoints are required
      return true if related_replica_count.blank?

      related_replica_count > 0
    end

    def selector
      @definition["spec"].fetch("selector", {})
    end

    def related_replica_count
      return 0 unless selector.present?
      return unless @related_deployments.length == 1
      @related_deployments.first["spec"]["replicas"].to_i
    end

    def external_name_svc?
      @definition["spec"]["type"] == "ExternalName"
    end
  end
end
