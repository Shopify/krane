# frozen_string_literal: true
module KubernetesDeploy
  class Service < KubernetesResource
    TIMEOUT = 7.minutes

    def sync
      _, _err, st = kubectl.run("get", type, @name)
      @found = st.success?
      if @found
        endpoints, _err, st = kubectl.run("get", "endpoints", @name, "--output=jsonpath={.subsets[*].addresses[*].ip}")
        @num_endpoints = (st.success? ? endpoints.split.length : 0)
      else
        @num_endpoints = 0
      end
      @status = "#{@num_endpoints} endpoints"
    end

    def deploy_succeeded?
      if exposes_zero_replica_deployment?
        @num_endpoints == 0
      else
        @num_endpoints > 0
      end
    end

    def deploy_failed?
      false
    end

    def timeout_message
      <<-MSG.strip_heredoc.strip
        This service does not have any endpoints. If the related pods are failing, fixing them will solve this as well.
        If the related pods are up, this service's selector is probably incorrect.
      MSG
    end

    def exists?
      @found
    end

    private

    def exposes_zero_replica_deployment?
      related_deployment_replicas && related_deployment_replicas == 0
    end

    def related_deployment_replicas
      @related_deployment_replicas ||= begin
        selector = @definition["spec"]["selector"].map { |k, v| "#{k}=#{v}" }.join(",")
        raw_json, _err, st = kubectl.run("get", "deployments", "--selector=#{selector}", "--output=json")
        return unless st.success?

        deployments = JSON.parse(raw_json)["items"]
        return unless deployments.length == 1
        deployments.first["spec"]["replicas"].to_i
      end
    end
  end
end
