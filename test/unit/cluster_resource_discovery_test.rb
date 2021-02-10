# frozen_string_literal: true
require 'test_helper'

class ClusterResourceDiscoveryTest < Krane::TestCase
  include ClusterResourceDiscoveryHelper

  def test_fetch_resources_failure
    crd = mocked_cluster_resource_discovery(success: false)
    assert_raises_message(Krane::FatalKubeAPIError, "Error retrieving raw path /:") do
      crd.fetch_resources
    end
  end

  def test_fetch_resources_not_namespaced
    crd = mocked_cluster_resource_discovery
    kinds = crd.fetch_resources(namespaced: false).map { |r| r['kind'] }
    assert_equal(kinds.length, 22)
    %w(MutatingWebhookConfiguration ComponentStatus CustomResourceDefinition).each do |kind|
      assert_includes(kinds, kind)
    end
  end

  def test_fetch_resources_namespaced
    crd = mocked_cluster_resource_discovery
    kinds = crd.fetch_resources(namespaced: true).map { |r| r['kind'] }
    assert_equal(kinds.length, 29)
    %w(ConfigMap CronJob Deployment).each do |kind|
      assert_includes(kinds, kind)
    end
  end

  def test_prunable_global_resources
    crd = mocked_cluster_resource_discovery
    kinds = crd.prunable_resources(namespaced: false)
    assert_equal(kinds.length, 15)
    %w(PriorityClass StorageClass).each do |expected_kind|
      assert(kinds.one? { |k| k.include?(expected_kind) })
    end
    %w(/node /namespace).each do |black_listed_kind|
      assert_empty(kinds.select { |k| k.downcase.end_with?(black_listed_kind) })
    end
  end

  def test_prunable_namespaced_resources
    crd = mocked_cluster_resource_discovery
    kinds = crd.prunable_resources(namespaced: true)

    assert_equal(kinds.length, 25)
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
    %w(batch/v1/Job extensions/v1beta1/Ingress).each do |expected_kind|
      assert(kinds.one? { |k| k.include?(expected_kind) })
    end
  end
end
