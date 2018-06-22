# frozen_string_literal: true
module KubernetesDeploy
  class Statefulservice < KubernetesResource
    def deploy_method
      :replace
    end
  end
end
