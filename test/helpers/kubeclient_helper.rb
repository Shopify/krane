# frozen_string_literal: true
module KubeclientHelper
  MINIKUBE_CONTEXT = "minikube"

  def kubeclient
    @kubeclient ||= build_kube_client("v1")
  end

  def v1beta1_kubeclient
    @v1beta1_kubeclient ||= build_kube_client("v1beta1", "/apis/extensions/")
  end

  def build_kube_client(api_version, endpoint_path="")
    config = Kubeclient::Config.read(ENV["KUBECONFIG"])
    unless config.contexts.include?(MINIKUBE_CONTEXT)
      raise "`#{MINIKUBE_CONTEXT}` context must be configured in your KUBECONFIG (#{ENV["KUBECONFIG"]}). Please see the README."
    end
    minikube = config.context(MINIKUBE_CONTEXT)

    client = Kubeclient::Client.new(
      "#{minikube.api_endpoint}#{endpoint_path}",
      api_version,
      {
        ssl_options: minikube.ssl_options,
        auth_options: minikube.auth_options
      }
    )
    client.discover
    client
  end
end
