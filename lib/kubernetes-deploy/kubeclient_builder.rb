# frozen_string_literal: true
require 'kubeclient'
require 'kubernetes-deploy/kubeclient_builder/google_friendly_config'

module KubernetesDeploy
  module KubeclientBuilder
    class ContextMissingError < FatalDeploymentError
      def initialize(context_name)
        super("`#{context_name}` context must be configured in your " \
          "KUBECONFIG file(s) (#{ENV['KUBECONFIG']}).")
      end
    end

    private

    def build_v1_kubeclient(context)
      _build_kubeclient(
        api_version: "v1",
        context: context
      )
    end

    def build_v1beta1_kubeclient(context)
      _build_kubeclient(
        api_version: "v1beta1",
        context: context,
        endpoint_path: "/apis/extensions/"
      )
    end

    def build_policy_v1beta1_kubeclient(context)
      _build_kubeclient(
        api_version: "v1beta1",
        context: context,
        endpoint_path: "/apis/policy/"
      )
    end

    def build_apps_v1beta1_kubeclient(context)
      _build_kubeclient(
        api_version: "v1beta1",
        context: context,
        endpoint_path: "/apis/apps"
      )
    end

    def _build_kubeclient(api_version:, context:, endpoint_path: nil)
      # Find a context defined in kube conf files that matches the input context by name
      kube_context = nil
      config_files.each do |f|
        config = GoogleFriendlyConfig.read(f)
        if config.contexts.include?(context)
          kube_context = config.context(context)
          break
        end
      end
      unless kube_context
        raise ContextMissingError, context
      end

      client = Kubeclient::Client.new(
        "#{kube_context.api_endpoint}#{endpoint_path}",
        api_version,
        ssl_options: kube_context.ssl_options,
        auth_options: kube_context.auth_options
      )
      client.discover
      client
    end

    def config_files
      # Split the list by colon for Linux and Mac, and semicolon for Windows.
      ENV.fetch("KUBECONFIG").tr(":;", " ").split
    end
  end
end
