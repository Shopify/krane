# frozen_string_literal: true
module KubernetesDeploy
  class PodDisruptionBudget < KubernetesResource
    TIMEOUT = 10.seconds

    def sync
      _, _err, st = kubectl.run("get", type, @name)
      @found = st.success?
      @status = @found ? "Available" : "Unknown"
    end

    def deploy_succeeded?
      exists?
    end

    def deploy_method
      # Required until https://github.com/kubernetes/kubernetes/issues/45398 changes
      :replace_force
    end

    def timeout_message
      UNUSUAL_FAILURE_MESSAGE
    end

    def exists?
      @found
    end
  end
end
