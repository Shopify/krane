$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'kubernetes-deploy'
require 'kubeclient'
require 'pry'

require 'minitest/autorun'

ENV["KUBECONFIG"] ||= "#{Dir.home}/.kube/config"

module KubeclientHelpers
  def kubeclient
    @kubeclient ||= begin
      config = Kubeclient::Config.read(ENV["KUBECONFIG"])
      unless config.contexts.include?("minikube")
        raise "`minikube` context should be configured in your KUBECONFIG (#{ENV["KUBECONFIG"]})"
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

Minitest::Test.include(KubeclientHelpers)

module TestProvisioner
  extend KubeclientHelpers

  def self.claim_namespace
    ns = SecureRandom.hex(8)
    create_namespace(ns)
    ns
  rescue KubeException => e
    retry if e.to_s.include?("already exists")
  end

  def self.create_namespace(namespace)
    ns = Kubeclient::Namespace.new
    ns.metadata = { name: namespace }
    kubeclient.create_namespace(ns)
  end

  def self.delete_namespace(namespace)
    kubeclient.delete_namespace(namespace)
  rescue KubeException => e
    raise unless e.to_s.include?("not found")
  end

  def self.prepare_pv(name)
    begin
      kubeclient.get_persistent_volume(name)
    rescue KubeException => e
      raise unless e.to_s.include?("not found")
      pv = Kubeclient::PersistentVolume.new
      pv.metadata = { name: name }
      pv.spec = {
        accessModes: ["ReadWriteOnce"],
        capacity: { storage: "1Gi" },
        hostPath: { path: "/data/#{name}" },
        persistentVolumeReclaimPolicy: "Recycle"
      }
      kubeclient.create_persistent_volume(pv)
    end
  end
end

TestProvisioner.prepare_pv("pv0001")
