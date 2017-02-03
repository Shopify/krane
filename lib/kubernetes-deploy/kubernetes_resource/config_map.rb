module KubernetesDeploy
  class ConfigMap < KubernetesResource
    TIMEOUT = 30.seconds

    def initialize(name, namespace, context, file)
      @name, @namespace, @context, @file = name, namespace, context, file
    end

    def sync
      _, st = run_kubectl("get", type, @name)
      @status = st.success? ? "Available" : "Unknown"
      @found = st.success?
      log_status
    end

    def deploy_succeeded?
      exists?
    end

    def deploy_failed?
      false
    end

    def exists?
      @found
    end
  end
end
