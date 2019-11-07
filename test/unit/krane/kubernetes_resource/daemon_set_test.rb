# frozen_string_literal: true
require 'test_helper'

class DaemonSetTest < Krane::TestCase
  include ResourceCacheTestHelper

  def test_deploy_not_successful_when_updated_available_does_not_match
    ds_template = build_ds_template(filename: 'daemon_set.yml')
    ds = build_synced_ds(ds_template: ds_template)
    refute_predicate(ds, :deploy_succeeded?)
  end

  def test_deploy_succeeded_not_fooled_by_stale_status
    status = {
      "observedGeneration": 1,
      "numberReady": 2,
      "desiredNumberScheduled": 2,
      "updatedNumberScheduled": 2,
    }
    ds_template = build_ds_template(filename: 'daemon_set.yml', status: status)
    ds = build_synced_ds(ds_template: ds_template)
    refute_predicate(ds, :deploy_succeeded?)
  end

  def test_deploy_failed_ensures_controller_has_observed_deploy
    ds_template = build_ds_template(filename: 'daemon_set.yml', status: { "observedGeneration": 1 })
    ds = build_synced_ds(ds_template: ds_template)
    ds.stubs(:pods).returns([stub(deploy_failed?: true)])
    refute_predicate(ds, :deploy_failed?)
  end

  def test_deploy_passes_when_updated_available_does_match
    status = {
      "currentNumberScheduled": 3,
      "desiredNumberScheduled": 2,
      "numberReady": 2,
      "updatedNumberScheduled": 2,
      "observedGeneration": 2,
    }

    ds_template = build_ds_template(filename: 'daemon_set.yml', status: status)
    ds = build_synced_ds(ds_template: ds_template)
    assert_predicate(ds, :deploy_succeeded?)
  end

  def test_deploy_passes_when_ready_pods_for_one_node
    status = {
      "desiredNumberScheduled": 1,
      "updatedNumberScheduled": 1,
    }
    ds_template = build_ds_template(filename: 'daemon_set.yml', status: status)
    pod_templates = load_fixtures(filenames: ['daemon_set_pod.yml'])
    node_templates = load_fixtures(filenames: ['node.yml'])
    ds = build_synced_ds(ds_template: ds_template, pod_templates: pod_templates, node_templates: node_templates)
    assert_predicate(ds, :deploy_succeeded?)
  end

  def test_deploy_passes_when_ready_pods_but_nodes_added
    status = {
      "desiredNumberScheduled": 1,
      "updatedNumberScheduled": 1,
      "numberReady": 0,
    }
    ds_template = build_ds_template(filename: 'daemon_set.yml', status: status)
    pod_templates = load_fixtures(filenames: ['daemon_set_pod_not_ready.yml'])
    node_templates = load_fixtures(filenames: ['node.yml'])
    ds = build_synced_ds(ds_template: ds_template, pod_templates: pod_templates, node_templates: node_templates)
    refute_predicate(ds, :deploy_succeeded?)

    node_added_status = {
      "desiredNumberScheduled": 3,
      "updatedNumberScheduled": 3,
      "numberReady": 2,
    }
    ds_template = build_ds_template(filename: 'daemon_set.yml', status: node_added_status)
    pod_templates = load_fixtures(filenames: ['daemon_set_pods.yml'])

    stub_kind_get("DaemonSet", items: [ds_template])
    stub_kind_get("Pod", items: pod_templates)
    ds.sync(build_resource_cache)
    assert_predicate(ds, :deploy_succeeded?)
  end

  def test_deploy_fails_when_not_all_pods_updated
    status = {
      "desiredNumberScheduled": 2,
      "updatedNumberScheduled": 1,
      "numberReady": 1,
    }
    ds_template = build_ds_template(filename: 'daemon_set.yml', status: status)
    pod_templates = load_fixtures(filenames: ['daemon_set_pod.yml'])
    node_templates = load_fixtures(filenames: ['node.yml'])
    ds = build_synced_ds(ds_template: ds_template, pod_templates: pod_templates, node_templates: node_templates)
    refute_predicate(ds, :deploy_succeeded?)
  end

  def test_deploy_fails_when_not_all_pods_ready
    status = {
      "desiredNumberScheduled": 3,
      "updatedNumberScheduled": 3,
      "numberReady": 2,
    }
    ds_template = build_ds_template(filename: 'daemon_set.yml', status: status)
    pod_templates = load_fixtures(filenames: ['daemon_set_pods.yml'])
    node_templates = load_fixtures(filenames: ['nodes.yml'])
    ds = build_synced_ds(ds_template: ds_template, pod_templates: pod_templates, node_templates: node_templates)
    refute_predicate(ds, :deploy_succeeded?)
  end

  private

  def build_ds_template(filename:, status: {})
    base_ds_manifest = YAML.load_stream(File.read(File.join(fixture_path('for_unit_tests'), filename))).first
    base_ds_manifest.deep_merge("status" => status)
  end

  def load_fixtures(filenames:)
    filenames.each_with_object([]) do |filename, manifests|
      manifest = YAML.load(File.read(File.join(fixture_path('for_unit_tests'), filename)))
      if manifest['kind'] == 'List'
        manifests.concat(manifest['items'])
      else
        manifests << manifest
      end
    end
  end

  def build_synced_ds(ds_template:, pod_templates: [], node_templates: [])
    ds = Krane::DaemonSet.new(namespace: "test", context: "nope", logger: logger, definition: ds_template)
    stub_kind_get("DaemonSet", items: [ds_template])
    stub_kind_get("Pod", items: pod_templates)
    stub_kind_get("Node", items: node_templates, use_namespace: false)
    ds.sync(build_resource_cache)
    ds
  end
end
