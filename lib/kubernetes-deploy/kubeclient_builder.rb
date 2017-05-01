# frozen_string_literal: true
require 'kubeclient'
require 'kubernetes-deploy/kubeclient_builder/google_friendly_config'

module KubernetesDeploy
  module KubeclientBuilder
    class ContextMissingError < FatalDeploymentError
      def initialize(context_name)
        super("`#{context_name}` context must be configured in your KUBECONFIG (#{ENV['KUBECONFIG']}). " \
          "Please see the README.")
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

    def _build_kubeclient(api_version:, context:, endpoint_path: nil)
      config = GoogleFriendlyConfig.read(ENV.fetch("KUBECONFIG"))
      unless config.contexts.include?(context)
        raise ContextMissingError, context
      end
      kube_context = config.context(context)

      client = Kubeclient::Client.new(
        "#{kube_context.api_endpoint}#{endpoint_path}",
        api_version,
        ssl_options: kube_context.ssl_options,
        auth_options: kube_context.auth_options
      )
      client.discover
      client
    end
  end
end
