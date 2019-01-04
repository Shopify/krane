# frozen_string_literal: true

require_relative './kubeclient_helper'

class TestProvisioner
  extend KubeclientHelper

  class << self
    def prepare_cluster
      WebMock.allow_net_connect!
      $stderr.print("Preparing test cluster... ")
      prepare_pv("pv0001")
      prepare_pv("pv0002")
      deploy_metric_server
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
      raise unless e.to_s.include?("not found")
    end

    private

    def create_namespace(namespace)
      ns = Kubeclient::Resource.new(kind: 'Namespace')
      ns.metadata = { name: namespace }
      kubeclient.create_namespace(ns)
    end

    def prepare_pv(name)
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
      kubeclient.create_persistent_volume(pv)
    end

    def deploy_metric_server
      # Set-up the metric server that the HPA needs https://github.com/kubernetes-incubator/metrics-server
      logger = KubernetesDeploy::FormattedLogger.build("default", KubeclientHelper::TEST_CONTEXT, $stderr)
      kubectl = KubernetesDeploy::Kubectl.new(namespace: "kube-system", context: KubeclientHelper::TEST_CONTEXT,
        logger: logger, log_failure_by_default: true, default_timeout: '5s')

      Dir.glob("test/setup/metrics-server/*.{yml,yaml}*").map do |resource|
        found = kubectl.run("get", "-f", resource, log_failure: false).last.success?
        kubectl.run("create", "-f", resource) unless found
      end
    end
  end
end
