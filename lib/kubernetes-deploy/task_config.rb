# frozen_string_literal: true
module KubernetesDeploy
  class TaskConfig
    include KubeclientBuilder

    attr_reader :errors, :warnings

    def initialize(context, namespace, required_args: {}, extra_config: {})
      @context = context
      @namespace = namespace
      @required_args = required_args.merge(namespace: namespace, context: context)
      @extra_config = extra_config
      reset_results
    end

    def valid?
      validate
      errors.empty?
    end

    def validate
      reset_results
      validate_required_args
      validate_kubeconfig
      return if errors.present?

      validate_context
      return if errors.present?

      validate_cluster_reachable
      return if errors.present?

      validate_server_version
      validate_namespace_exists
      validate_task_specifics
    end

    def record_result(logger)
      warnings.each do |warning|
        logger.warn(warning)
      end

      return unless errors.present?
      logger.summary.add_action("Configuration invalid")
      logger.summary.add_paragraph(errors.map { |err| "- #{err}" }.join("\n"))
    end

    def error_sentence
      return "" if errors.empty?
      "Configuration invalid: #{errors.join(', ')}"
    end

    private

    def validate_task_specifics
    end

    def reset_results
      @errors = []
      @warnings = []
    end

    def validate_required_args
      required_args.each do |name, value|
        @errors << "#{name} cannot be blank" unless value.present?
      end
    end

    def validate_kubeconfig
      if ENV["KUBECONFIG"].blank?
        @errors << "KUBECONFIG environment variable cannot be blank"
      elsif config_files.empty?
        @errors << "KUBECONFIG environment variable must reference valid files"
      else
        config_files.each do |f|
          next if File.file?(f)
          @errors << "Kube config not found at #{f}"
        end
      end
    end

    def validate_context
      available_contexts = kubeclient_configs.flat_map(&:contexts).uniq
      unless available_contexts.include?(@context)
        @errors << "Context #{@context} is not available. Valid contexts: #{available_contexts}"
      end
    end

    def validate_cluster_reachable
      response = ping_api_server(retries: 2)
      unless response.code == 200
        @errors << "Context #{@context} is unreachable"
      end
    end

    def ping_api_server(retries:)
      get_raw('healthz', retries: retries)
    end

    def validate_server_version
      version = get_server_version
      return unless version.present?

      if version < Gem::Version.new(MIN_KUBE_VERSION)
        @warnings << KubernetesDeploy::Errors.server_version_warning(kubectl.server_version)
      end
    end

    def server_version_warning(server_version)
      "Minimum cluster version requirement of #{MIN_KUBE_VERSION} not met. "\
      "Using #{server_version} could result in unexpected behavior as it is no longer tested against"
    end

    def get_server_version(retries:)
      resp = get_raw('version', retries: retries)
      return unless resp.code == 200
      version_string = JSON.parse(resp)["gitVersion"]
      Gem::Version.new(version_string.delete('v'))
    end

    def get_raw(endpoint, retries:)
      (retries + 1).times do
        resp = raw_client[endpoint].get
        break if resp.code == 200
      end
      resp
    end

    def raw_client
      @raw_client ||= build_raw_client(@context)
    end

    def validate_namespace_exists
      return unless @namespace.present?
      with_kube_exception_retries { kubeclient.get_namespace(@namespace) }
    rescue Kubeclient::ResourceNotFoundError
      @errors << "Namespace #{@namespace} not found"
    rescue Kubeclient::HttpError => error
      @errors << "Failed to reach namespace #{@namespace}: #{error}"
    end

    def kubeclient
      @kubeclient ||= build_v1_kubeclient(@context)
    end
  end
end
