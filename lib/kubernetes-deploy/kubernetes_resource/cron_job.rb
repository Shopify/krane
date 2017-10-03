# frozen_string_literal: true
module KubernetesDeploy
  class CronJob < KubernetesResource
    TIMEOUT = 30.seconds
    PRUNABLE = true

    def deploy_succeeded?
      exists?
    end

    def deploy_failed?
      !exists?
    end

    def timeout_message
      UNUSUAL_FAILURE_MESSAGE
    end
  end
end
