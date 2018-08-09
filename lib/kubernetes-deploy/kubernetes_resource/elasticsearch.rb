# frozen_string_literal: true
module KubernetesDeploy
  class Elasticsearch < KubernetesResource
    def deploy_succeeded?
      super # success assumption, with warning
    end

    def deploy_failed?
      false
    end
  end
end
