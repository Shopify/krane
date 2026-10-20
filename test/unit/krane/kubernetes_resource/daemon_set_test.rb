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
    stub_kind_get("Node", items: node_templates, use_namespace: false)
    ds.sync(build_resource_cache)
    assert_predicate(ds, :deploy_succeeded?)
  end

  def test_deploy_passes_when_nodes_unschedulable
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

    # node 2 Pod Ready status is False, if the node is unschedulable it should not account as blocking
    node_templates[2]['spec']['unschedulable'] = 'true'

    stub_kind_get("DaemonSet", items: [ds_template])
    stub_kind_get("Pod", items: pod_templates)
    stub_kind_get("Node", items: node_templates, use_namespace: false)
    ds.sync(build_resource_cache)
    assert_predicate(ds, :deploy_succeeded?)
  end

  def test_deploy_passes_when_nodes_not_ready
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

    # node 2 Pod Ready status is False, if the node is not ready it should not account as blocking
    node_templates[2]['status']['conditions'].find { |c| c['type'].downcase == 'ready' }['status'] = 'False'

    stub_kind_get("DaemonSet", items: [ds_template])
    stub_kind_get("Pod", items: pod_templates)
    stub_kind_get("Node", items: node_templates, use_namespace: false)
    ds.sync(build_resource_cache)
    assert_predicate(ds, :deploy_succeeded?)
  end

  def test_deploy_passes_when_pod_evicted
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

    pod_templates[2]["status"] = {
      "message": "Pod The node had condition: [DiskPressure].",
      "phase": "Failed",
      "reason": "Evicted",
      "startTime": "2022-03-31T20:14:06Z"
    }

    stub_kind_get("DaemonSet", items: [ds_template])
    stub_kind_get("Pod", items: pod_templates)
    stub_kind_get("Node", items: node_templates, use_namespace: false)
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

  def test_deploy_waits_for_daemonset_status_to_converge_to_pod_states
    status = {
      "desiredNumberScheduled": 1,
      "updatedNumberScheduled": 1,
      "numberReady": 0,
    }
    ds_template = build_ds_template(filename: 'daemon_set.yml', status: status)
    ready_pod_template = load_fixtures(filenames: ['daemon_set_pods.yml']).first # should be a pod in `Ready` state
    node_templates = load_fixtures(filenames: ['nodes.yml'])
    ds = build_synced_ds(ds_template: ds_template, pod_templates: [ready_pod_template], node_templates: node_templates)
    refute_predicate(ds, :deploy_succeeded?)

    status[:numberReady] = 1
    ds_template = build_ds_template(filename: 'daemon_set.yml', status: status)
    stub_kind_get("DaemonSet", items: [ds_template])
    stub_kind_get("Pod", items: [ready_pod_template])
    stub_kind_get("Node", items: node_templates, use_namespace: false)
    ds.sync(build_resource_cache)
    assert_predicate(ds, :deploy_succeeded?)
  end

  def test_deploy_succeeded_with_none_annotation
    status = {
      "desiredNumberScheduled": 3,
      "updatedNumberScheduled": 1,
      "numberReady": 0,
    }
    ds_template = build_ds_template(filename: 'daemon_set.yml', status: status, rollout: 'none')
    pod_templates = load_fixtures(filenames: ['daemon_set_pod_not_ready.yml'])
    node_templates = load_fixtures(filenames: ['node.yml'])
    ds = build_synced_ds(ds_template: ds_template, pod_templates: pod_templates, node_templates: node_templates)
    assert_predicate(ds, :deploy_succeeded?)
  end

  def test_deploy_succeeded_with_max_unavailable
    status = {
      "desiredNumberScheduled": 3,
      "updatedNumberScheduled": 3,
      "numberReady": 2,
    }
    ds_template = build_ds_template(filename: 'daemon_set.yml', status: status, 
      rollout: 'maxUnavailable', max_unavailable: 1)
    pod_templates = load_fixtures(filenames: ['daemon_set_pods.yml'])
    node_templates = load_fixtures(filenames: ['nodes.yml'])
    ds = build_synced_ds(ds_template: ds_template, pod_templates: pod_templates, node_templates: node_templates)
    assert_predicate(ds, :deploy_succeeded?)
  end

  def test_deploy_not_succeeded_with_max_unavailable_when_below_threshold
    status = {
      "desiredNumberScheduled": 3,
      "updatedNumberScheduled": 3,
      "numberReady": 1,
    }
    ds_template = build_ds_template(filename: 'daemon_set.yml', status: status,
      rollout: 'maxUnavailable', max_unavailable: 1)
    pod_templates = load_fixtures(filenames: ['daemon_set_pods.yml'])
    node_templates = load_fixtures(filenames: ['nodes.yml'])
    ds = build_synced_ds(ds_template: ds_template, pod_templates: pod_templates, node_templates: node_templates)
    refute_predicate(ds, :deploy_succeeded?)
  end

  def test_deploy_succeeded_with_percentage_rollout
    status = {
      "desiredNumberScheduled": 3,
      "updatedNumberScheduled": 3,
      "numberReady": 2,
    }
    ds_template = build_ds_template(filename: 'daemon_set.yml', status: status, rollout: '66%')
    pod_templates = load_fixtures(filenames: ['daemon_set_pods.yml'])
    node_templates = load_fixtures(filenames: ['nodes.yml'])
    ds = build_synced_ds(ds_template: ds_template, pod_templates: pod_templates, node_templates: node_templates)
    assert_predicate(ds, :deploy_succeeded?)
  end

  def test_deploy_not_succeeded_with_percentage_rollout_when_below_threshold
    status = {
      "desiredNumberScheduled": 3,
      "updatedNumberScheduled": 3,
      "numberReady": 1,
    }
    ds_template = build_ds_template(filename: 'daemon_set.yml', status: status, rollout: '67%')
    pod_templates = load_fixtures(filenames: ['daemon_set_pods.yml'])
    node_templates = load_fixtures(filenames: ['nodes.yml'])
    ds = build_synced_ds(ds_template: ds_template, pod_templates: pod_templates, node_templates: node_templates)
    refute_predicate(ds, :deploy_succeeded?)
  end

  def test_deploy_succeeded_raises_with_invalid_rollout_annotation
    status = {
      "desiredNumberScheduled": 3,
      "updatedNumberScheduled": 3,
      "numberReady": 3,
    }
    ds_template = build_ds_template(filename: 'daemon_set.yml', status: status, rollout: 'bad')
    pod_templates = load_fixtures(filenames: ['daemon_set_pods.yml'])
    node_templates = load_fixtures(filenames: ['nodes.yml'])
    ds = build_synced_ds(ds_template: ds_template, pod_templates: pod_templates, node_templates: node_templates)

    msg = "'#{rollout_annotation_key}: bad' is invalid. " \
      "Acceptable values: #{Krane::DaemonSet::REQUIRED_ROLLOUT_TYPES.join(', ')}, or a percentage (e.g. 90%)"

    assert_raises_message(Krane::FatalDeploymentError, msg) do
      ds.deploy_succeeded?
    end
  end

  def test_validation_fails_with_invalid_rollout_annotation
    ds_template = build_ds_template(filename: 'daemon_set.yml', rollout: 'bad')
    ds = build_synced_ds(ds_template: ds_template)
    
    stub_validation_dry_run(err: "super failed", status: SystemExit.new(1))
    
    refute(ds.validate_definition(kubectl: kubectl))

    expected = <<~STRING.strip
      super failed
      '#{rollout_annotation_key}: bad' is invalid. Acceptable values: #{Krane::DaemonSet::REQUIRED_ROLLOUT_TYPES.join(', ')}, or a percentage (e.g. 90%)
    STRING
    assert_equal(expected, ds.validation_error_msg)
  end

  def test_validation_with_percent_rollout_annotation
    ds_template = build_ds_template(filename: 'daemon_set.yml', rollout: '90%')
    ds = build_synced_ds(ds_template: ds_template)
    
    stub_validation_dry_run
    
    assert(ds.validate_definition(kubectl: kubectl))
    assert_empty(ds.validation_error_msg)
  end

  def test_validation_fails_with_invalid_mix_of_annotation
    ds_template = build_ds_template(filename: 'daemon_set.yml', rollout: 'maxUnavailable', 
      update_strategy: 'OnDelete')
    ds = build_synced_ds(ds_template: ds_template)
    
    stub_validation_dry_run(err: "super failed", status: SystemExit.new(1))
    
    refute(ds.validate_definition(kubectl: kubectl))

    expected = <<~STRING.strip
      super failed
      '#{rollout_annotation_key}: maxUnavailable' is incompatible with updateStrategy 'OnDelete'
    STRING
    assert_equal(expected, ds.validation_error_msg)
  end

  private

  def stub_validation_dry_run(out: "", err: "", status: SystemExit.new(0))
    kubectl.expects(:run)
      .with('apply', '-f', anything, '--dry-run=client', '--output=name', anything)
      .returns([out, err, status])
  end

  def build_ds_template(filename:, status: {}, rollout: nil, max_unavailable: nil, update_strategy: nil)
    base_ds_manifest = YAML.load_stream(File.read(File.join(fixture_path('for_unit_tests'), filename))).first
    result = base_ds_manifest.deep_merge("status" => status)
    
    if rollout
      result["metadata"] ||= {}
      result["metadata"]["annotations"] ||= {}
      result["metadata"]["annotations"][rollout_annotation_key] = rollout
    end

    if max_unavailable
      result["spec"]["updateStrategy"] ||= { "type" => "RollingUpdate" }
      result["spec"]["updateStrategy"]["rollingUpdate"] = { "maxUnavailable" => max_unavailable }
    end

    if update_strategy
      result["spec"]["updateStrategy"] = { "type" => update_strategy }
    end

    result
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

  def kubectl
    @kubectl ||= build_runless_kubectl
  end

  def rollout_annotation_key
    Krane::Annotation.for(Krane::DaemonSet::REQUIRED_ROLLOUT_ANNOTATION)
  end
end
