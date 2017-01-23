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
        puts "`minikube` context should be configured in your KUBECONFIG (#{ENV["KUBECONFIG"]})"
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

  def self.prepare_namespace(namespace)
    begin
      kubeclient.get_namespace(namespace)
    rescue KubeException
      ns = Kubeclient::Namespace.new
      ns.metadata = { name: namespace }
      kubeclient.create_namespace(ns)
    end
  end

  def self.prepare_pv(name)
    begin
      kubeclient.get_persistent_volume(name)
    rescue KubeException
      pv = Kubeclient::PersistentVolume.new
      pv.metadata = { name: name }
      pv.spec = {
        accessModes: ["ReadWriteOnce"],
        capacity: { storage: "1Gi" },
        hostPath: { path: "/data/#{name}" }
      }
      kubeclient.create_persistent_volume(pv)
    end
  end
end

TestProvisioner.prepare_namespace("trashbin")
TestProvisioner.prepare_pv("pv0001")
