# frozen_string_literal: true
module KubernetesDeploy
  class TaskConfigValidator
    DEFAULT_VALIDATIONS = %i(
      validate_kubeconfig
      validate_context_exists_in_kubeconfig
      validate_context_reachable
      validate_server_version
      validate_namespace_exists
    ).freeze

    delegate :context, :namespace, :logger, to: :@task_config

    def initialize(task_config, kubectl, kubeclient_builder, only: nil)
      @task_config = task_config
      @kubectl = kubectl
      @kubeclient_builder = kubeclient_builder
      @errors = nil
      @validations = only || DEFAULT_VALIDATIONS
    end

    def valid?
      @errors = []
      @validations.each do |validator_name|
        break if @errors.present?
        send(validator_name)
      end
      @errors.empty?
    end

    def errors
      valid?
      @errors
    end

    private

    def validate_kubeconfig
      @errors += @kubeclient_builder.validate_config_files
    end

    def validate_context_exists_in_kubeconfig
      unless context.present?
        return @errors << "Context can not be blank"
      end

      _, err, st = @kubectl.run("config", "get-contexts", context, "-o", "name",
        use_namespace: false, use_context: false, log_failure: false)

      unless st.success?
        @errors << if err.match("error: context #{context} not found")
          "Context #{context} missing from your kubeconfig file(s)"
        else
          "Something went wrong. #{err} "
        end
      end
    end

    def validate_context_reachable
      _, err, st = @kubectl.run("get", "namespaces", "-o", "name",
        use_namespace: false, log_failure: false)

      unless st.success?
        @errors << "Something went wrong connecting to #{context}. #{err} "
      end
    end

    def validate_namespace_exists
      unless namespace.present?
        return @errors << "Namespace can not be blank"
      end

      _, err, st = @kubectl.run("get", "namespace", "-o", "name", namespace,
        use_namespace: false, log_failure: false)

      unless st.success?
        @errors << if err.match("Error from server [(]NotFound[)]: namespace")
          "Could not find Namespace: #{namespace} in Context: #{context}"
        else
          "Could not connect to kubernetes cluster. #{err}"
        end
      end
    end

    def validate_server_version
      if @kubectl.server_version < Gem::Version.new(MIN_KUBE_VERSION)
        logger.warn(server_version_warning(@kubectl.server_version))
      end
    end

    def server_version_warning(server_version)
      "Minimum cluster version requirement of #{MIN_KUBE_VERSION} not met. "\
      "Using #{server_version} could result in unexpected behavior as it is no longer tested against"
    end
  end
end
