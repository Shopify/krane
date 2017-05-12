# frozen_string_literal: true
module KubernetesDeploy
  class PersistentVolumeClaim < KubernetesResource
    TIMEOUT = 5.minutes

    def sync
      out, _err, st = kubectl.run("get", type, @name, "--output=jsonpath={.status.phase}")
      @found = st.success?
      @status = out if @found
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
