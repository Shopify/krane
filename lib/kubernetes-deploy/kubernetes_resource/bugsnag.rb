# frozen_string_literal: true
module KubernetesDeploy
  class Bugsnag < KubernetesResource
    TIMEOUT = 1.minute

    def initialize(name, namespace, context, file)
      @name = name
      @namespace = namespace
      @context = context
      @file = file
      @secret_found = false
    end

    def sync
      _, _err, st = run_kubectl("get", type, @name)
      @found = st.success?
      if @found
        secrets, _err, _st = run_kubectl("get", "secrets", "--output=name")
        @secret_found = secrets.split.any? { |s| s.end_with?("-bugsnag") }
      end
      @status = @secret_found ? "Available" : "Unknown"
      log_status
    end

    def deploy_succeeded?
      @secret_found
    end

    def deploy_failed?
      false
    end

    def exists?
      @found
    end

    def tpr?
      true
    end
  end
end
