module KubeclientHelper
  def kubeclient
    @kubeclient ||= begin
      config = Kubeclient::Config.read(ENV["KUBECONFIG"])
      unless config.contexts.include?("minikube")
        raise "`minikube` context must be configured in your KUBECONFIG (#{ENV["KUBECONFIG"]}). Please see the README."
      end

      client = Kubeclient::Client.new(
        config.context.api_endpoint,
        config.context.api_version,
        {
          ssl_options: config.context.ssl_options,
          auth_options: config.context.auth_options
        }
      )
      client.discover
      client
    end
  end
end
