# frozen_string_literal: true
module KubernetesDeploy
  class Topic < KubernetesResource
    def deploy_method
      :replace
    end
  end
end
