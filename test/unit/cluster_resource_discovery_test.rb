# frozen_string_literal: true
require 'test_helper'

class ClusterResourceDiscoveryTest < Krane::TestCase
  include ClusterResourceDiscoveryHelper

  def test_fetch_resources_failure
    crd = mocked_cluster_resource_discovery(success: false)
    assert_raises_message(Krane::FatalKubeAPIError, "Error retrieving cluster url:") do
      crd.fetch_resources
    end
  end

  def test_fetch_resources_not_namespaced
    crd = mocked_cluster_resource_discovery
    kinds = crd.fetch_resources(namespaced: false).map { |r| r['kind'] }.uniq
    assert_equal(20, kinds.length)
    %w(MutatingWebhookConfiguration ComponentStatus CustomResourceDefinition).each do |kind|
      assert_includes(kinds, kind)
    end
  end

  def test_fetch_resources_namespaced
    crd = mocked_cluster_resource_discovery
    kinds = crd.fetch_resources(namespaced: true).map { |r| r['kind'] }.uniq
    assert_equal(27, kinds.length)
    %w(ConfigMap CronJob Deployment).each do |kind|
      assert_includes(kinds, kind)
    end
  end

  def test_prunable_global_resources
    crd = mocked_cluster_resource_discovery
    kinds = crd.prunable_resources(namespaced: false).map { |k| k.split('/').last }.uniq
    assert_equal(13, kinds.length)
    %w(PriorityClass StorageClass).each do |expected_kind|
      assert(kinds.one? { |k| k.include?(expected_kind) })
    end
    %w(/node /namespace).each do |black_listed_kind|
      assert_empty(kinds.select { |k| k.downcase.end_with?(black_listed_kind) })
    end
  end

  def test_prunable_namespaced_resources
    crd = mocked_cluster_resource_discovery
    kinds = crd.prunable_resources(namespaced: true).map { |k| k.split('/').last }.uniq

    assert_equal(24, kinds.length)
    %w(ConfigMap CronJob Deployment).each do |expected_kind|
      assert(kinds.one? { |k| k.include?(expected_kind) })
    end
    %w(controllerrevision).each do |black_listed_kind|
      assert_empty(kinds.select { |k| k.downcase.include?(black_listed_kind) })
    end
  end

  def test_prunable_namespaced_resources_apply_group_version_kind_overrides
    crd = mocked_cluster_resource_discovery
    kinds = crd.prunable_resources(namespaced: true)
    %w(batch/v1/Job networking.k8s.io/v1/NetworkPolicy).each do |expected_kind|
      assert(kinds.one? { |k| k.include?(expected_kind) })
    end
  end

  def test_fetch_group_kinds
    crd = ::Krane::ClusterResourceDiscovery.new(task_config: task_config, namespace_tags: [])
    stub_api_resources

    group_kinds = crd.fetch_group_kinds
    assert_equal(125, group_kinds.length)

    r_deployment = group_kinds.find { |gk| gk.group_kind == "Deployment.apps" }
    assert(r_deployment.namespaced)

    r_storage_class = group_kinds.find { |gk| gk.group_kind == "StorageClass.storage.k8s.io" }
    refute(r_storage_class.namespaced)

    r_pod_template = group_kinds.find { |gk| gk.group_kind == "PodTemplate." }
    assert(r_pod_template.namespaced)
  end
end
