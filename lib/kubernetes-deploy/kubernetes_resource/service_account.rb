# frozen_string_literal: true
module KubernetesDeploy
  class ServiceAccount < KubernetesResource
    TIMEOUT = 1.minutes

    def sync
      raw_json, _err, st = kubectl.run("get", type, @name, "--output=json")
      @found = st.success?
    end

    def deploy_succeeded?
        @found
    end

    def deploy_failed?
      !@found
    end

    # def failure_message
    #   "Service Account failed"
    # end

    def exists?
      @found
    end
  end
end
