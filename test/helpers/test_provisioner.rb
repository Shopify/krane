# frozen_string_literal: true

require_relative './kubeclient_helper'

class TestProvisioner
  extend KubeclientHelper

  class << self
    def prepare_cluster
      WebMock.allow_net_connect!
      $stderr.print("Preparing test cluster... ")
      [ENV['PARALLELISM'].to_i, 4].max.times { |i| prepare_pv("pv000#{i}") }
      $stderr.puts "Done."
      WebMock.disable_net_connect!
    end

    def claim_namespace(test_name)
      prefix = "k8sdeploy-"
      suffix = "-#{SecureRandom.hex(8)}"
      max_base_length = 63 - (prefix + suffix).length # namespace name length must be <= 63 chars
      ns_name = prefix + test_name.gsub(/[^-a-z0-9]/, '-').slice(0, max_base_length) + suffix

      create_namespace(ns_name)
      ns_name
    end

    def delete_namespace(namespace)
      kubeclient.delete_namespace(namespace) if namespace.present?
    rescue KubeException => e
      raise unless e.is_a?(Kubeclient::ResourceNotFoundError)
    end

    def prepare_pv(name, storage_class_name: nil)
      existing_pvs = kubeclient.get_persistent_volumes(label_selector: "name=#{name}")
      return if existing_pvs.present?

      pv = Kubeclient::Resource.new(kind: 'PersistentVolume')
      pv.metadata = {
        name: name,
        labels: { name: name },
      }
      pv.spec = {
        accessModes: %w(ReadWriteOnce),
        capacity: { storage: "150Mi" },
        hostPath: { path: "/data/#{name}" },
        persistentVolumeReclaimPolicy: "Recycle",
      }
      pv.spec[:storageClassName] = storage_class_name if storage_class_name.present?

      kubeclient.create_persistent_volume(pv)
    end

    private

    def wait_for_default_service_account(kubeclient, namespace)
      30.times do
        begin
          sa = kubeclient.get_service_account('default', namespace)
          return if sa
        rescue Kubeclient::ResourceNotFoundError
          # If the service account is not found, sleep for a second and then retry
          sleep(1)
        end
      end
      raise "Default service account in #{namespace} not ready after 30 seconds"
    end

    def create_namespace(namespace)
      ns = Kubeclient::Resource.new(kind: 'Namespace')
      ns.metadata = { name: namespace }
      kubeclient.create_namespace(ns)
      # wait for the serviceaccount 'default' to be created; https://github.com/kubernetes/kubernetes/issues/66689
      wait_for_default_service_account(kubeclient, namespace)
    end
  end
end
