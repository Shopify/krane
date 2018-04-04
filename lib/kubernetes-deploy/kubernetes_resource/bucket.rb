# frozen_string_literal: true
module KubernetesDeploy
  class Bucket < KubernetesResource
    def deploy_succeeded?
      return false unless deploy_started?

      unless @success_assumption_warning_shown
        @logger.warn("Don't know how to monitor resources of type #{type}. Assuming #{id} deployed successfully.")
        @success_assumption_warning_shown = true
      end
      true
    end

    def status
      exists? ? "Available" : "Unknown"
    end

    def deploy_failed?
      false
    end

    def deploy_method
      :replace
    end
  end
end
