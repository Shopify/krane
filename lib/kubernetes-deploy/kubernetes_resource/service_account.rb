# frozen_string_literal: true
module KubernetesDeploy
  class ServiceAccount < KubernetesResource
    TIMEOUT = 30.seconds

    def sync
      _, _err, st = kubectl.run("get", type, @name, "--output=json")
      @found = st.success?
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
