# frozen_string_literal: true
module Krane
  class Ingress < KubernetesResource
    TIMEOUT = 30.seconds

    def status
      exists? ? "Created" : "Not Found"
    end

    def deploy_succeeded?
      exists?
    end

    def deploy_failed?
      false
    end
    
    def predeployed?
      krane_annotation_value("predeployed") == "true"
    end

  end
end
