# frozen_string_literal: true
module KubernetesDeploy
  class PersistentVolumeClaim < KubernetesResource
    TIMEOUT = 5.minutes
    PREDEPLOY = true

    def status
      exists? ? @instance_data["status"]["phase"] : "Unknown"
    end

    def deploy_succeeded?
      status == "Bound"
    end

    def deploy_failed?
      status == "Lost"
    end
  end
end
