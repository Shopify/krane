module KubeclientHelper
  MINIKUBE_CONTEXT = "minikube".freeze

  def kubeclient
    @kubeclient ||= begin
      config = Kubeclient::Config.read(ENV["KUBECONFIG"])
      unless config.contexts.include?(MINIKUBE_CONTEXT)
        raise "`#{MINIKUBE_CONTEXT}` context must be configured in your KUBECONFIG (#{ENV["KUBECONFIG"]}). Please see the README."
      end
      minikube = config.context(MINIKUBE_CONTEXT)

      client = Kubeclient::Client.new(
        minikube.api_endpoint,
        minikube.api_version,
        {
          ssl_options: minikube.ssl_options,
          auth_options: minikube.auth_options
        }
      )
      client.discover
      client
    end
  end
end
