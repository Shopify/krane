# frozen_string_literal: true
module KubernetesDeploy
  class Elasticsearch < KubernetesResource
    def deploy_method
      :replace
    end
  end
end
