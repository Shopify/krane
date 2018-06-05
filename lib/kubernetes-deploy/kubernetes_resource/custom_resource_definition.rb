# frozen_string_literal: true
module KubernetesDeploy
  class CustomResourceDefinition < KubernetesResource
    TIMEOUT = 30.seconds

    def deploy_succeeded?
      names_accepted_status == "True"
    end

    def deploy_failed?
      names_accepted_status == "False"
    end

    def timeout_message
      UNUSUAL_FAILURE_MESSAGE
    end

    private

    def names_accepted_status
      conditions = @instance_data.dig("status", "conditions") || []
      names_accepted = conditions.detect { |c| c["type"] == "NamesAccepted" } || {}
      names_accepted["status"]
    end
  end
end
