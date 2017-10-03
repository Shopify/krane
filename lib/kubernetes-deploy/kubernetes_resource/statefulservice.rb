# frozen_string_literal: true
module KubernetesDeploy
  class Statefulservice < KubernetesResource
    GROUP = 'stable.shopify.io'
    VERSION = 'v1'

    def deploy_succeeded?
      super # success assumption, with warning
    end

    def deploy_failed?
      false
    end

    def deploy_method
      :replace
    end
  end
end
