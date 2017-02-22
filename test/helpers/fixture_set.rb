require 'helpers/kubeclient_helper'

module FixtureSetAssertions
  class FixtureSet
    class FixtureSetError < StandardError; end
    include KubeclientHelper
    include Minitest::Assertions
    attr_writer :assertions

    def initialize
      raise NotImplementedError
    end

    def assertions
      @assertions ||= 0
    end

    def namespace
      raise FixtureSetError.new("@namespace must be set in initializer") if @namespace.blank?
      @namespace
    end

    def app_name
      raise FixtureSetError.new("@app_name must be set in initializer") if @app_name.blank?
      @app_name
    end

    def refute_resource_exists(type, name, beta: false)
      client = beta ? v1beta1_kubeclient : kubeclient
      resources = client.public_send("get_#{type}", name, namespace) # 404s
      flunk "#{type} #{name} unexpectedly existed"
    rescue KubeException => e
      raise unless e.to_s.include?("not found")
    end

    def assert_pod_status(pod_name, status, count=1)
      pods = kubeclient.get_pods(namespace: namespace, label_selector: "name=#{pod_name},app=#{app_name}")
      num_with_status = pods.count { |pod| pod.status.phase == status }
      assert_equal count, num_with_status, "Expected to find #{count} #{pod_name} pods with status #{status}, found #{num_with_status}"
    end

    def assert_service_up(svc_name)
      services = kubeclient.get_services(namespace: namespace, label_selector: "name=#{svc_name},app=#{app_name}")
      assert_equal 1, services.size, "Expected 1 #{svc_name} service, got #{services.size}"
      refute services.first["spec"]["clusterIP"].empty?, "Cluster IP was not assigned"

      endpoints_obj = kubeclient.get_endpoint(svc_name, namespace)
      num_endpoints = endpoints_obj["subsets"].first["addresses"].length
      assert_equal 1, num_endpoints
    end

    def assert_deployment_up(dep_name, replicas)
      deployments = v1beta1_kubeclient.get_deployments(namespace: namespace, label_selector: "name=#{dep_name},app=#{app_name}")
      assert_equal 1, deployments.size, "Expected 1 #{dep_name} deployment, got #{deployments.size}"
      available = deployments.first["status"]["availableReplicas"]
      assert_equal replicas, available, "Expected #{dep_name} deployment to have #{replicas} available replicas, saw #{available}"
    end

    def assert_pvc_status(pvc_name, status)
      pvc = kubeclient.get_persistent_volume_claims(namespace: namespace, label_selector: "name=#{pvc_name},app=#{app_name}")
      assert_equal 1, pvc.size, "Expected 1 #{pvc_name} pvc, saw #{pvc.size}"
      assert_equal status, pvc.first.status.phase
    end

    def assert_ingress_up(ing_name)
      ing = v1beta1_kubeclient.get_ingresses(namespace: namespace, label_selector: "name=#{ing_name},app=#{app_name}")
      assert_equal 1, ing.size, "Expected 1 #{ing_name} ingress, got #{ing.size}"
    end

    def assert_configmap_present(cm_name, expected_data)
      configmaps = kubeclient.get_config_maps(namespace: namespace, label_selector: "name=#{cm_name},app=#{app_name}")
      assert_equal 1, configmaps.size, "Expected 1 configmap, got #{configmaps.size}"
      assert_equal expected_data, configmaps.first["data"].to_h
    end
  end
end
