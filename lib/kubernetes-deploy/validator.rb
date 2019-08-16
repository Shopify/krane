# frozen_string_literal: true
module KubernetesDeploy
  class Validator
    DEFAULT_VALIDATIONS = %i(
      validate_kubeconfig
      validate_context_exists
      validate_namespace_exists
      validate_server_version
    ).freeze

    delegate :context, :namespace, :logger, :kubectl, :kubeclient_builder, to: :@task_config

    def initialize(task_config)
      @task_config = task_config
      @errors = nil
    end

    def valid?
      @errors = []
      DEFAULT_VALIDATIONS.each do |validator_name|
        send(validator_name)
        break if @errors.present?
      end
      @errors.empty?
    end

    def errors
      valid?
      @errors
    end

    private

    def validate_kubeconfig
      @errors += kubeclient_builder.validate_config_files
    end

    def validate_context_exists
      unless context.present?
        return @errors << "Context can not be blank"
      end

      _, err, st = kubectl.run("config", "get-contexts", context, "-o", "name",
        use_namespace: false, use_context: false, log_failure: false)

      unless st.success?
        @errors << if err.match("error: context #{context} not found")
          "Context #{context} missing from your kubeconfig file(s)"
        else
          "Something went wrong. #{err} "
        end
        return
      end

      _, err, st = kubectl.run("get", "namespaces", "-o", "name",
        use_namespace: false, log_failure: false)

      unless st.success?
        @errors << "Something went wrong connectting to #{context}. #{err} "
      end
    end

    def validate_namespace_exists
      unless namespace.present?
        return @errors << "Namespace can not be blank"
      end

      _, err, st = kubectl.run("get", "namespace", "-o", "name", namespace,
        use_namespace: false, log_failure: false)

      unless st.success?
        @errors << if err.match("Error from server [(]NotFound[)]: namespace")
          "Cloud not find Namespace: #{namespace} in Context: #{context}"
        else
          "Could not connect to kubernetes cluster. #{err}"
        end
      end
    end

    def validate_server_version
      if kubectl.server_version < Gem::Version.new(MIN_KUBE_VERSION)
        logger.warn(KubernetesDeploy::Errors.server_version_warning(kubectl.server_version))
      end
    end
  end
end
