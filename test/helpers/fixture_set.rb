# frozen_string_literal: true
require 'helpers/kubeclient_helper'
require 'base64'

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
      raise FixtureSetError, "@namespace must be set in initializer" if @namespace.blank?
      @namespace
    end

    def app_name
      raise FixtureSetError, "@app_name must be set in initializer" if @app_name.blank?
      @app_name
    end

    def refute_resource_exists(type, name, beta: false)
      client = beta ? v1beta1_kubeclient : kubeclient
      client.public_send("get_#{type}", name, namespace) # 404s
      flunk "#{type} #{name} unexpectedly existed"
    rescue KubeException => e
      raise unless e.to_s.include?("not found")
    end

    def assert_pod_status(pod_name, status, count = 1)
      pods = kubeclient.get_pods(namespace: namespace, label_selector: "name=#{pod_name},app=#{app_name}")
      num_with_status = pods.count { |pod| pod.status.phase == status }

      msg = "Expected to find #{count} #{pod_name} pods with status #{status}, found #{num_with_status}"
      assert_equal count, num_with_status, msg
    end

    def assert_service_up(svc_name)
      services = kubeclient.get_services(namespace: namespace, label_selector: "name=#{svc_name},app=#{app_name}")
      assert_equal 1, services.size, "Expected 1 #{svc_name} service, got #{services.size}"
      refute services.first["spec"]["clusterIP"].empty?, "Cluster IP was not assigned"

      endpoints_obj = kubeclient.get_endpoint(svc_name, namespace)
      num_endpoints = endpoints_obj["subsets"].first["addresses"].length
      assert_equal 1, num_endpoints
    end

    def assert_deployment_up(dep_name, replicas:)
      deployments = v1beta1_kubeclient.get_deployments(
        namespace: namespace,
        label_selector: "name=#{dep_name},app=#{app_name}"
      )
      assert_equal 1, deployments.size, "Expected 1 #{dep_name} deployment, got #{deployments.size}"
      available = deployments.first["status"]["availableReplicas"]

      msg = "Expected #{dep_name} deployment to have #{replicas} available replicas, saw #{available}"
      assert_equal replicas, available, msg
    end

    def assert_pvc_status(pvc_name, status)
      pvc = kubeclient.get_persistent_volume_claims(
        namespace: namespace,
        label_selector: "name=#{pvc_name},app=#{app_name}"
      )
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

    def assert_pod_templates_present(cm_name)
      pod_templates = kubeclient.get_pod_templates(
        namespace: namespace,
        label_selector: "name=#{cm_name},app=#{app_name}"
      )
      assert_equal 1, pod_templates.size, "Expected 1 podtemplate, got #{pod_templates.size}"
    end

    def assert_secret_present(secret_name, expected_data = nil, type: 'Opaque', managed: false)
      secrets = kubeclient.get_secrets(namespace: namespace, label_selector: "name=#{secret_name}")
      assert_equal 1, secrets.size, "Expected 1 secret, got #{secrets.size}"
      secret = secrets.first
      assert_annotated(secret, KubernetesDeploy::EjsonSecretProvisioner::MANAGEMENT_ANNOTATION) if managed
      assert_equal type, secret["type"]
      return unless expected_data

      secret_data = secret["data"].to_h.stringify_keys
      secret_data.each do |key, value|
        secret_data[key] = Base64.decode64(value)
      end
      assert_equal expected_data, secret_data
    end

    def assert_annotated(obj, annotation)
      annotations = obj.metadata.annotations.to_h.stringify_keys
      assert annotations.key?(annotation), "Expected secret to have annotation #{annotation}, but it did not"
    end
  end
end
