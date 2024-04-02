# frozen_string_literal: true
require 'test_helper'

class StatefulSetTest < Krane::TestCase
  include ResourceCacheTestHelper

  def test_deploy_succeeded_true_with_rolling_update_strategy
    ss = build_synced_ss(ss_template: build_ss_template)
    assert_predicate(ss, :deploy_succeeded?)
  end

  def test_deploy_succeeded_true_with_on_delete_strategy_and_no_rollout_annotation
    # OnDelete strategy without rollout annotation should always succeed.
    # Change the updateRevision to ensure it's not being used to determine success.
    ss_template = build_ss_template(status: { "updateRevision": 3 }, updateStrategy: "OnDelete", rollout: nil)
    ss = build_synced_ss(ss_template: ss_template)
    assert_predicate(ss, :deploy_succeeded?)
  end

  def test_deploy_succeeded_true_with_on_delete_strategy_and_full_rollout_annotation
    ss_template = build_ss_template(status: { "updateRevision": 3 }, updateStrategy: "OnDelete", rollout: nil)
    ss = build_synced_ss(ss_template: ss_template)
    assert_predicate(ss, :deploy_succeeded?)
  end

  def test_deploy_does_not_succeed_when_revision_does_not_match_without_annotation
    ss_template = build_ss_template(status: { "updateRevision": 1 }, rollout: nil)
    ss = build_synced_ss(ss_template: ss_template)
    refute_predicate(ss, :deploy_succeeded?)
  end

  def test_deploy_succeeded_when_replica_counts_match_for_ondelete_strategy_with_full_annotation
    ss_template = build_ss_template(updateStrategy: "OnDelete", rollout: "full")
    ss = build_synced_ss(ss_template: ss_template)
    assert_predicate(ss, :deploy_succeeded?)
  end

  def test_deploy_does_not_succeed_when_replica_counts_do_not_match_for_ondelete_strategy_with_full_annotation
    ss_template = build_ss_template(status: { "readyReplicas": 1 }, updateStrategy: "OnDelete", rollout: "full")
    ss = build_synced_ss(ss_template: ss_template)
    refute_predicate(ss, :deploy_succeeded?)
  end

  def test_deploy_does_not_succeed_when_replica_counts_do_not_match_for_rollingupdate_strategy
    ss_template = build_ss_template(status: { "updatedReplicas": 1 }, updateStrategy: "RollingUpdate", rollout: nil)
    ss = build_synced_ss(ss_template: ss_template)
    refute_predicate(ss, :deploy_succeeded?)
  end

  def test_deploy_does_not_succeed_when_current_and_observed_generations_do_not_match
    ss_template = build_ss_template(status: { "observedGeneration": 1 })
    ss = build_synced_ss(ss_template: ss_template)
    refute_predicate(ss, :deploy_succeeded?)
  end

  def test_deploy_failed_not_fooled_by_stale_status_for_rollingupdate_strategy
    status = {
      "observedGeneration": 1,
      "readyReplicas": 0,
    }
    ss_template = build_ss_template(status: status, updateStrategy: "RollingUpdate")
    ss = build_synced_ss(ss_template: ss_template)
    ss.stubs(:pods).returns([stub(deploy_failed?: true)])
    refute_predicate(ss, :deploy_failed?)
  end

  def test_deploy_failed_not_fooled_by_stale_status_for_ondelete_strategy
    status = {
      "observedGeneration": 1,
      "readyReplicas": 0,
    }
    ss_template = build_ss_template(status: status, updateStrategy: "OnDelete")
    ss = build_synced_ss(ss_template: ss_template)
    ss.stubs(:pods).returns([stub(deploy_failed?: true)])
    refute_predicate(ss, :deploy_failed?)
  end

  private

  def build_ss_template(status: {}, updateStrategy: "RollingUpdate", rollout: "full")
    ss_fixture.dup.deep_merge(
      "status" => status,
      "spec" => {"updateStrategy" => {"type" => updateStrategy}},
      "metadata" => {"annotations" => {"krane.shopify.io/required-rollout" => rollout}}
    )
  end

  def build_synced_ss(ss_template:, pod_template: pod_fixture)
    ss = Krane::StatefulSet.new(namespace: "test", context: "nope", logger: logger, definition: ss_template)
    stub_kind_get("StatefulSet", items: [ss_template])
    stub_kind_get("Pod", items: [pod_template])
    ss.sync(build_resource_cache)
    ss
  end

  def ss_fixture
    @ss_fixture ||= YAML.load_stream(
      File.read(File.join(fixture_path('for_unit_tests'), 'stateful_set_test.yml'))
    ).find { |fixture| fixture["kind"] == "StatefulSet" }
  end

  def pod_fixture
    @pod_fixture ||= YAML.load_stream(
      File.read(File.join(fixture_path('for_unit_tests'), 'stateful_set_pod_test.yml'))
    ).find { |fixture| fixture["kind"] == "Pod" }
  end
end
