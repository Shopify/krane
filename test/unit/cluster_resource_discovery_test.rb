# frozen_string_literal: true
require 'test_helper'

class ClusterResourceDiscoveryTest < Krane::TestCase
  include ClusterResourceDiscoveryHelper

  def test_fetch_resources_failure
    crd = mocked_cluster_resource_discovery(nil, success: false)
    resources = crd.fetch_resources
    assert_equal(resources, [])
  end

  def test_fetch_resources_not_namespaced
    crd = mocked_cluster_resource_discovery(api_resources_not_namespaced_full_response)
    kinds = crd.fetch_resources(namespaced: false).map { |r| r['kind'] }
    assert_equal(kinds.length, api_resources_not_namespaced_full_response.split("\n").length - 1)
    %w(MutatingWebhookConfiguration ComponentStatus CustomResourceDefinition).each do |kind|
      assert_includes(kinds, kind)
    end
  end

  def test_fetch_resources_namespaced
    crd = mocked_cluster_resource_discovery(api_resources_namespaced_full_response, namespaced: true)
    kinds = crd.fetch_resources(namespaced: true).map { |r| r['kind'] }
    assert_equal(kinds.length, api_resources_namespaced_full_response.split("\n").length - 1)
    %w(ConfigMap CronJob Deployment).each do |kind|
      assert_includes(kinds, kind)
    end
  end

  def test_prunable_global_resources
    Krane::Kubectl.any_instance.stubs(:run).with("api-versions", attempts: 5, use_namespace: false)
      .returns([api_versions_full_response, "", stub(success?: true)])
    crd = mocked_cluster_resource_discovery(api_resources_not_namespaced_full_response)
    kinds = crd.prunable_resources(namespaced: false)

    assert_equal(kinds.length, 12)
    %w(PriorityClass StorageClass).each do |expected_kind|
      assert kinds.one? { |k| k.include?(expected_kind) }
    end
    %w(node namespace).each do |black_lised_kind|
      assert_empty kinds.select { |k| k.downcase.include?(black_lised_kind) }
    end
  end

  def test_prunable_namespaced_resources
    Krane::Kubectl.any_instance.stubs(:run).with("api-versions", attempts: 5, use_namespace: false)
      .returns([api_versions_full_response, "", stub(success?: true)])
    crd = mocked_cluster_resource_discovery(api_resources_namespaced_full_response, namespaced: true)
    kinds = crd.prunable_resources(namespaced: true)

    assert_equal(kinds.length, 25)
    %w(ConfigMap CronJob Deployment).each do |expected_kind|
      assert kinds.one? { |k| k.include?(expected_kind) }
    end
  end

  def test_prunable_namespaced_resources_apply_group_version_kind_overrides
    Krane::Kubectl.any_instance.stubs(:run).with("api-versions", attempts: 5, use_namespace: false)
      .returns([api_versions_full_response, "", stub(success?: true)])
    crd = mocked_cluster_resource_discovery(api_resources_namespaced_full_response, namespaced: true)
    kinds = crd.prunable_resources(namespaced: true)

    %w(batch/v1/Job extensions/v1beta1/Ingress).each do |expected_kind|
      assert kinds.one? { |k| k.include?(expected_kind) }
    end
  end
end
