# frozen_string_literal: true
module KubernetesDeploy
  class CustomResourceDefinition < KubernetesResource
    TIMEOUT = 10.seconds
    PREDEPLOY = true

    def sync(mediator)
      @instance_data = mediator.get_instance(kind, name)
    end

    def deploy_succeeded?
      exists?
    end

    def deploy_failed?
      false
    end

    def timeout_message
      UNUSUAL_FAILURE_MESSAGE
    end

    def exists?
      !@instance_data.empty?
    end
  end
end
