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
    # Change updatedReplicas to ensure it's not being used to determine success.
    ss_template = build_ss_template(status: { "updatedReplicas": 0 }, updateStrategy: "OnDelete", rollout: nil)
    ss = build_synced_ss(ss_template: ss_template)
    assert_predicate(ss, :deploy_succeeded?)
  end

  def test_deploy_succeeded_true_with_on_delete_strategy_and_full_rollout_annotation
    ss_template = build_ss_template(updateStrategy: "OnDelete", rollout: "full")
    ss = build_synced_ss(ss_template: ss_template)
    assert_predicate(ss, :deploy_succeeded?)
  end

  def test_deploy_succeeded_false_when_updated_replicas_dont_match_desired
    ss_template = build_ss_template(status: { "updatedReplicas": 1 })
    ss = build_synced_ss(ss_template: ss_template)
    refute_predicate(ss, :deploy_succeeded?)
  end

  def test_deploy_does_not_succeed_when_replica_counts_do_not_match_for_ondelete_strategy_with_full_annotation
    ss_template = build_ss_template(status: { "updatedReplicas": 1 }, updateStrategy: "OnDelete", rollout: "full")
    ss = build_synced_ss(ss_template: ss_template)
    refute_predicate(ss, :deploy_succeeded?)
  end

  def test_deploy_does_not_succeed_when_current_and_observed_generations_do_not_match
    ss_template = build_ss_template(status: { "observedGeneration": 1 })
    ss = build_synced_ss(ss_template: ss_template)
    refute_predicate(ss, :deploy_succeeded?)
  end

  def test_deploy_failed_not_fooled_by_stale_status
    status = {
      "observedGeneration": 1,
      "readyReplicas": 0,
    }
    ss_template = build_ss_template(status: status)
    ss = build_synced_ss(ss_template: ss_template)
    ss.stubs(:pods).returns([stub(deploy_failed?: true)])
    refute_predicate(ss, :deploy_failed?)
  end

  def test_deploy_failed_ignores_current_pods
    current_pod = pod_fixture.deep_merge(
      "metadata" => {
        "labels" => {
          "controller-revision-hash" => "current",
        },
      },
      "status" => {
        "phase" => "Failed",
      },
    )

    ss_status = {
      "observedGeneration" => 2,
      "currentRevision" => "current",
      "updateRevision" => "updated",
    }
    ss = build_synced_ss(ss_template: build_ss_template(status: ss_status), pod_template: current_pod)
    refute_predicate(ss, :deploy_failed?)
  end

  def test_deploy_failed_considers_updated_pods
    updated_pod = pod_fixture.deep_merge(
      "metadata" => {
        "labels" => {
          "controller-revision-hash" => "updated",
        },
      },
      "status" => {
        "phase" => "Failed",
      },
    )

    ss_status = {
      "observedGeneration" => 2,
      "currentRevision" => "current",
      "updateRevision" => "updated",
    }
    ss = build_synced_ss(ss_template: build_ss_template(status: ss_status), pod_template: updated_pod)
    assert_predicate(ss, :deploy_failed?)
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
