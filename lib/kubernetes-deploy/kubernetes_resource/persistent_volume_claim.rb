module KubernetesDeploy
  class PersistentVolumeClaim < KubernetesResource
    TIMEOUT = 5.minutes

    def initialize(name, namespace, file)
      @name, @namespace, @file = name, namespace, file
    end

    def sync
      @status, st = run_kubectl("get", type, @name, "--output=jsonpath={.status.phase}")
      @found = st.success?
      log_status
    end

    def deploy_succeeded?
      @status == "Bound"
    end

    def deploy_failed?
      @status == "Lost"
    end

    def exists?
      @found
    end
  end
end
