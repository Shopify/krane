# frozen_string_literal: true
module KubernetesDeploy
  class Mail < KubernetesResource
    GROUP = 'stable.shopify.io'
    PREDEPLOY = true
    TIMEOUT = 30.seconds
    VERSION = 'v1'

    def sync
      _, _err, st = kubectl.run("get", type, @name)
      @found = st.success?
    end

    def deploy_succeeded?
      exists?
    end

    def exists?
      @found
    end

    def deploy_failed?
      false
    end
  end
end
