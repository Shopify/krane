module KubernetesDeploy
  class Cloudsql < KubernetesResource
    TIMEOUT = 30.seconds

    def initialize(name, namespace, file)
      @name, @namespace, @file = name, namespace, file
    end

    def sync
      _, st = run_kubectl("get", type, @name)
      @found = st.success?
      @status = true
      log_status
    end

    def deploy_succeeded?
      exists?
    end

    def deploy_failed?
      false
    end

    def tpr?
      true
    end

    def exists?
      @found
    end
  end
end
