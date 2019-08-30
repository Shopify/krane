# frozen_string_literal: true
require 'kubeclient'

module KubernetesDeploy
  class KubeclientBuilder
    class ContextMissingError < FatalDeploymentError
      def initialize(context_name, kubeconfig)
        super("`#{context_name}` context must be configured in your " \
          "KUBECONFIG file(s) (#{kubeconfig.join(', ')}).")
      end
    end

    def initialize(kubeconfig: ENV["KUBECONFIG"])
      files = kubeconfig || "#{Dir.home}/.kube/config"
      # Split the list by colon for Linux and Mac, and semicolon for Windows.
      @kubeconfig_files = files.split(/[:;]/).map!(&:strip).reject(&:empty?)
    end

    def build_v1_kubeclient(context)
      build_kubeclient(
        api_version: "v1",
        context: context
      )
    end

    def build_v1beta1_kubeclient(context)
      build_kubeclient(
        api_version: "v1beta1",
        context: context,
        endpoint_path: "/apis/extensions/"
      )
    end

    def build_batch_v1beta1_kubeclient(context)
      build_kubeclient(
        api_version: "v1beta1",
        context: context,
        endpoint_path: "/apis/batch/"
      )
    end

    def build_batch_v1_kubeclient(context)
      build_kubeclient(
        api_version: "v1",
        context: context,
        endpoint_path: "/apis/batch/"
      )
    end

    def build_policy_v1beta1_kubeclient(context)
      build_kubeclient(
        api_version: "v1beta1",
        context: context,
        endpoint_path: "/apis/policy/"
      )
    end

    def build_apps_v1beta1_kubeclient(context)
      build_kubeclient(
        api_version: "v1beta1",
        context: context,
        endpoint_path: "/apis/apps"
      )
    end

    def build_apiextensions_v1beta1_kubeclient(context)
      build_kubeclient(
        api_version: "v1beta1",
        context: context,
        endpoint_path: "/apis/apiextensions.k8s.io"
      )
    end

    def build_autoscaling_v1_kubeclient(context)
      build_kubeclient(
        api_version: "v2beta1",
        context: context,
        endpoint_path: "/apis/autoscaling"
      )
    end

    def build_rbac_v1_kubeclient(context)
      build_kubeclient(
        api_version: "v1",
        context: context,
        endpoint_path: "/apis/rbac.authorization.k8s.io"
      )
    end

    def build_networking_v1_kubeclient(context)
      build_kubeclient(
        api_version: "v1",
        context: context,
        endpoint_path: "/apis/networking.k8s.io"
      )
    end

    def build_storage_v1_kubeclient(context)
      build_kubeclient(
        api_version: "v1",
        context: context,
        endpoint_path: "/apis/storage.k8s.io"
      )
    end

    def validate_config_files
      errors = []
      if @kubeconfig_files.empty?
        errors << "Kubeconfig file name(s) not set in $KUBECONFIG"
      else
        @kubeconfig_files.each do |f|
          # If any files in the list are not valid, we can't be sure the merged context list is what the user intended
          errors << "Kubeconfig not found at #{f}" unless File.file?(f)
        end
      end
      errors
    end

    def validate_config_files!
      errors = validate_config_files
      raise TaskConfigurationError, errors.join(', ') if errors.present?
    end

    private

    def build_kubeclient(api_version:, context:, endpoint_path: nil)
      validate_config_files!
      @kubeclient_configs ||= @kubeconfig_files.map { |f| Kubeclient::Config.read(f) }
      # Find a context defined in kube conf files that matches the input context by name
      config = @kubeclient_configs.find { |c| c.contexts.include?(context) }
      raise ContextMissingError.new(context, @kubeconfig_files) unless config

      kube_context = config.context(context)
      client = Kubeclient::Client.new(
        "#{kube_context.api_endpoint}#{endpoint_path}",
        api_version,
        ssl_options: kube_context.ssl_options,
        auth_options: kube_context.auth_options,
        timeouts: {
          open: KubernetesDeploy::Kubectl::DEFAULT_TIMEOUT,
          read: KubernetesDeploy::Kubectl::DEFAULT_TIMEOUT,
        }
      )
      client.discover
      client
    end
  end
end
