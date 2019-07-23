# frozen_string_literal: true
require 'test_helper'

class HorizontalPodAutoscalerTest < KubernetesDeploy::TestCase
  include ResourceCacheTestHelper

  # We can't get integration coverage for HPA right now because the metrics server just isn't reliable enough on our CI
  def test_hpa_is_whitelisted_for_pruning
    KubernetesDeploy::Kubectl.any_instance.expects("run")
      .with("get", "CustomResourceDefinition", output: "json", attempts: 5)
      .returns(['{ "items": [] }', "", SystemExit.new(0)])
    task = KubernetesDeploy::DeployTask.new(namespace: 'test', context: KubeclientHelper::TEST_CONTEXT,
      current_sha: 'foo', template_paths: [''], logger: logger)
    assert(task.prune_whitelist.one? { |whitelisted_type| whitelisted_type.include?("HorizontalPodAutoscaler") })
  end

  def test_hpa_succeeds_when_scaling_is_active
    conditions = [{
      "lastTransitionTime" => 5.seconds.ago,
      "message" => "the HPA was able to successfully calculate a replica count from cpu "\
        "resource utilization (percentage of request)",
      "reason" => "ValidMetricFound",
      "status" => "True",
      "type" => "ScalingActive",
    }]
    hpa = build_synced_hpa(build_hpa_template(conditions: conditions))
    assert(hpa.deploy_succeeded?)
    refute(hpa.deploy_failed?)
    assert_equal("Configured", hpa.status)
  end

  def test_hpa_succeeds_if_scaling_is_explicitly_disabled
    conditions = [{
      "lastTransitionTime" => 5.seconds.ago,
      "message" => "scaling is disabled since the replica count of the target is zero",
      "reason" => "ScalingDisabled",
      "status" => "False",
      "type" => "ScalingActive",
    }]
    hpa = build_synced_hpa(build_hpa_template(conditions: conditions))
    assert(hpa.deploy_succeeded?)
    refute(hpa.deploy_failed?)
    assert_equal("ScalingDisabled", hpa.status)
  end

  def test_hpa_fails_when_scaling_not_active_and_unrecoverable
    conditions = [{
      "lastTransitionTime" => 5.seconds.ago,
      "message" => "the HPA target's scale is missing a selector",
      "reason" => "InvalidSelector",
      "status" => "False",
      "type" => "ScalingActive",
    }]
    hpa = build_synced_hpa(build_hpa_template(conditions: conditions))
    refute(hpa.deploy_succeeded?)
    assert(hpa.deploy_failed?)
    assert_equal("InvalidSelector", hpa.status)
    assert_equal("the HPA target's scale is missing a selector", hpa.failure_message)

    conditions = [{
      "lastTransitionTime" => 5.seconds.ago,
      "message" => "the HPA was unable to compute the replica count",
      "reason" => "InvalidMetricSourceType",
      "status" => "False",
      "type" => "ScalingActive",
    }]
    hpa = build_synced_hpa(build_hpa_template(conditions: conditions))
    refute(hpa.deploy_succeeded?)
    assert(hpa.deploy_failed?)
    assert_equal("InvalidMetricSourceType", hpa.status)
    assert_equal("the HPA was unable to compute the replica count", hpa.failure_message)
  end

  def test_hpa_does_not_fail_when_scaling_inactive_due_to_failed_get
    conditions = [{
      "lastTransitionTime" => 5.seconds.ago,
      "message" => "the HPA was unable to compute the replica count",
      "reason" => "FailedGetObjectMetric",
      "status" => "False",
      "type" => "ScalingActive",
    }]
    hpa = build_synced_hpa(build_hpa_template(conditions: conditions))
    refute(hpa.deploy_succeeded?)
    refute(hpa.deploy_failed?)
    assert_equal("FailedGetObjectMetric", hpa.status)
  end

  def test_hpa_timeouts_can_report_able_to_scale_condition_if_scaling_active_unavailable
    hpa = build_synced_hpa(build_hpa_template(conditions: []))
    hpa.deploy_started_at = (hpa.timeout + 5).seconds.ago
    assert(hpa.deploy_timed_out?)
    refute(hpa.deploy_succeeded?)
    refute(hpa.deploy_failed?)
    assert_equal("Unknown", hpa.status)

    conditions = [{
      "lastTransitionTime" => 5.seconds.ago,
      "message" => "the HPA controller was unable to update the target scale",
      "reason" => "FailedUpdateScale",
      "status" => "False",
      "type" => "AbleToScale",
    }]
    hpa = build_synced_hpa(build_hpa_template(conditions: conditions))
    hpa.deploy_started_at = (hpa.timeout + 5).seconds.ago
    assert(hpa.deploy_timed_out?)
    refute(hpa.deploy_succeeded?)
    refute(hpa.deploy_failed?)
    assert_equal("FailedUpdateScale", hpa.status)
    assert_equal("the HPA controller was unable to update the target scale", hpa.timeout_message)
  end

  private

  def build_hpa_template(conditions: [])
    hpa_fixture.dup.tap { |hpa| hpa["status"]["conditions"] = conditions }
  end

  def build_synced_hpa(template)
    hpa = KubernetesDeploy::HorizontalPodAutoscaler.new(
      namespace: 'test-ns',
      context: KubeclientHelper::TEST_CONTEXT,
      logger: logger,
      definition: template
    )
    stub_kind_get("hpa.v2beta1.autoscaling", items: [template])
    hpa.sync(build_resource_cache)
    hpa
  end

  def hpa_fixture
    @hpa_fixture ||= YAML.load_stream(
      File.read(File.join(fixture_path('for_unit_tests'), 'horizontal_pod_autoscaler_test.yml'))
    ).first
  end
end
