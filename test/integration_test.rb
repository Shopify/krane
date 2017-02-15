require 'helpers/kubeclient_helper'

module KubernetesDeploy
  class IntegrationTest < ::Minitest::Test
    include KubeclientHelper

    def setup
      @logger_stream = StringIO.new
      @logger = Logger.new(@logger_stream)
      KubernetesDeploy.logger = @logger
      @namespace = TestProvisioner.claim_namespace
    end

    def teardown
      @logger_stream.close
      TestProvisioner.delete_namespace(@namespace)
    end
  end

  module TestProvisioner
    extend KubeclientHelper

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
end
