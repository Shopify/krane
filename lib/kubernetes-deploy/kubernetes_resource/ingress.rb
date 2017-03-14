# frozen_string_literal: true
module KubernetesDeploy
  class Ingress < KubernetesResource
    TIMEOUT = 30.seconds

    def initialize(name, namespace, context, file)
      @name = name
      @namespace = namespace
      @context = context
      @file = file
    end

    def sync
      _, st = run_kubectl("get", type, @name)
      @status = st.success? ? "Created" : "Unknown"
      @found = st.success?
      log_status
    end

    def deploy_succeeded?
      exists?
    end

    def deploy_failed?
      false
    end

    def exists?
      @found
    end

    def group_name
      "Ingresses"
    end
  end
end
