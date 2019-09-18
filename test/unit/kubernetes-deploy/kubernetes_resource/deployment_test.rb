# frozen_string_literal: true
require 'test_helper'

class DeploymentTest < KubernetesDeploy::TestCase
  include ResourceCacheTestHelper

  def test_deploy_succeeded_with_none_annotation
    deployment_status = {
      "replicas" => 3,
      "updatedReplicas" => 1,
      "unavailableReplicas" => 1,
      "availableReplicas" => 0,
    }

    rs_status = {
      "replicas" => 3,
      "availableReplicas" => 0,
      "readyReplicas" => 0,
    }
    dep_template = build_deployment_template(status: deployment_status, rollout: 'none',
      strategy: 'RollingUpdate', max_unavailable: 1)
    deploy = build_synced_deployment(template: dep_template, replica_sets: [build_rs_template(status: rs_status)])
    assert(deploy.deploy_succeeded?)
  end

  def test_deploy_succeeded_is_false_with_none_annotation_before_new_rs_created
    deployment_status = {
      "replicas" => 3,
      "updatedReplicas" => 3,
      "unavailableReplicas" => 0,
      "availableReplicas" => 3,
    }
    deploy = build_synced_deployment(
      template: build_deployment_template(status: deployment_status, rollout: 'none'),
      replica_sets: []
    )
    refute(deploy.deploy_succeeded?)
  end

  def test_deploy_succeeded_with_max_unavailable
    deployment_status = {
      "replicas" => 3, # one terminating in old rs, one starting in new rs, one up in new rs
      "updatedReplicas" => 2,
      "unavailableReplicas" => 2,
      "availableReplicas" => 1,
    }

    rs_status = {
      "replicas" => 2,
      "availableReplicas" => 1,
      "readyReplicas" => 1,
    }
    replica_sets = [build_rs_template(status: rs_status)]

    deploy = build_synced_deployment(
      template: build_deployment_template(status: deployment_status, rollout: 'maxUnavailable', max_unavailable: 3),
      replica_sets: replica_sets
    )
    assert(deploy.deploy_succeeded?)

    deploy = build_synced_deployment(
      template: build_deployment_template(status: deployment_status, rollout: 'maxUnavailable', max_unavailable: 2),
      replica_sets: replica_sets
    )
    assert(deploy.deploy_succeeded?)

    deploy = build_synced_deployment(
      template: build_deployment_template(status: deployment_status, rollout: 'maxUnavailable', max_unavailable: 1),
      replica_sets: replica_sets
    )
    refute(deploy.deploy_succeeded?)

    deploy = build_synced_deployment(
      template: build_deployment_template(status: deployment_status, rollout: 'maxUnavailable', max_unavailable: 0),
      replica_sets: replica_sets
    )
    refute(deploy.deploy_succeeded?)
  end

  def test_deploy_succeeded_with_annotation_as_percent
    deployment_status = {
      "replicas" => 3, # one terminating in old rs, one starting in new rs, one up in new rs
      "updatedReplicas" => 2,
      "unavailableReplicas" => 2,
      "availableReplicas" => 1,
    }

    rs_status = {
      "replicas" => 2,
      "availableReplicas" => 1,
      "readyReplicas" => 1,
    }
    replica_sets = [build_rs_template(status: rs_status)]

    deploy = build_synced_deployment(
      template: build_deployment_template(status: deployment_status, rollout: '0%'),
      replica_sets: replica_sets
    )
    assert(deploy.deploy_succeeded?)

    deploy = build_synced_deployment(
      template: build_deployment_template(status: deployment_status, rollout: '33%'),
      replica_sets: replica_sets
    )
    assert(deploy.deploy_succeeded?)

    deploy = build_synced_deployment(
      template: build_deployment_template(status: deployment_status, rollout: '34%'),
      replica_sets: replica_sets
    )
    refute(deploy.deploy_succeeded?)

    deploy = build_synced_deployment(
      template: build_deployment_template(status: deployment_status, rollout: '100%'),
      replica_sets: replica_sets
    )
    refute(deploy.deploy_succeeded?)
  end

  def test_deploy_succeeded_with_max_unavailable_as_percent
    deployment_status = {
      "replicas" => 3,
      "updatedReplicas" => 2,
      "unavailableReplicas" => 2,
      "availableReplicas" => 1,
    }

    rs_status = {
      "replicas" => 2,
      "availableReplicas" => 1,
      "readyReplicas" => 1,
    }
    replica_sets = [build_rs_template(status: rs_status)]

    dep_template = build_deployment_template(status: deployment_status,
      rollout: 'maxUnavailable', max_unavailable: '100%')
    deploy = build_synced_deployment(template: dep_template, replica_sets: replica_sets)
    assert(deploy.deploy_succeeded?)

    # rounds up to two max
    deploy = build_synced_deployment(
      template: build_deployment_template(status: deployment_status, rollout: 'maxUnavailable', max_unavailable: '67%'),
      replica_sets: replica_sets
    )
    assert(deploy.deploy_succeeded?)

    # rounds down to one max
    deploy = build_synced_deployment(
      template: build_deployment_template(status: deployment_status, rollout: 'maxUnavailable', max_unavailable: '66%'),
      replica_sets: replica_sets
    )
    refute(deploy.deploy_succeeded?)

    deploy = build_synced_deployment(
      template: build_deployment_template(status: deployment_status, rollout: 'maxUnavailable', max_unavailable: '0%'),
      replica_sets: replica_sets
    )
    refute(deploy.deploy_succeeded?)
  end

  def test_deploy_succeeded_raises_with_invalid_rollout_annotation_deprecated
    deploy = build_synced_deployment(
      template: build_deployment_template(rollout: 'bad', use_deprecated: true),
      replica_sets: [build_rs_template]
    )
    msg = "'#{KubernetesDeploy::Deployment::REQUIRED_ROLLOUT_ANNOTATION_DEPRECATED}: bad' is "\
      "invalid. Acceptable values: #{KubernetesDeploy::Deployment::REQUIRED_ROLLOUT_TYPES.join(', ')}"
    assert_raises_message(KubernetesDeploy::FatalDeploymentError, msg) do
      deploy.deploy_succeeded?
    end
  end

  def test_deploy_succeeded_raises_with_invalid_rollout_annotation
    deploy = build_synced_deployment(
      template: build_deployment_template(rollout: 'bad'),
      replica_sets: [build_rs_template]
    )
    msg = "'#{KubernetesDeploy::Deployment::REQUIRED_ROLLOUT_ANNOTATION}: bad' is "\
      "invalid. Acceptable values: #{KubernetesDeploy::Deployment::REQUIRED_ROLLOUT_TYPES.join(', ')}"
    assert_raises_message(KubernetesDeploy::FatalDeploymentError, msg) do
      deploy.deploy_succeeded?
    end
  end

  def test_validation_fails_with_invalid_rollout_annotation_deprecated
    deploy = build_synced_deployment(
      template: build_deployment_template(rollout: 'bad', use_deprecated: true),
      replica_sets: []
    )
    kubectl.expects(:run).with('apply', '-f', anything, '--dry-run', '--output=name', anything).returns(
      ["", "super failed", SystemExit.new(1)]
    )
    refute(deploy.validate_definition(kubectl))

    expected = <<~STRING.strip
      super failed
      '#{KubernetesDeploy::Deployment::REQUIRED_ROLLOUT_ANNOTATION_DEPRECATED}: bad' is invalid. Acceptable values: #{KubernetesDeploy::Deployment::REQUIRED_ROLLOUT_TYPES.join(', ')}
    STRING
    assert_equal(expected, deploy.validation_error_msg)
  end

  def test_validation_fails_with_invalid_rollout_annotation
    deploy = build_synced_deployment(template: build_deployment_template(rollout: 'bad'), replica_sets: [])
    kubectl.expects(:run).with('apply', '-f', anything, '--dry-run', '--output=name', anything).returns(
      ["", "super failed", SystemExit.new(1)]
    )
    refute(deploy.validate_definition(kubectl))

    expected = <<~STRING.strip
      super failed
      '#{KubernetesDeploy::Deployment::REQUIRED_ROLLOUT_ANNOTATION}: bad' is invalid. Acceptable values: #{KubernetesDeploy::Deployment::REQUIRED_ROLLOUT_TYPES.join(', ')}
    STRING
    assert_equal(expected, deploy.validation_error_msg)
  end

  def test_validation_with_percent_rollout_annotation
    deploy = build_synced_deployment(template: build_deployment_template(rollout: '10%'), replica_sets: [])
    kubectl.expects(:run).with('apply', '-f', anything, '--dry-run', '--output=name', anything).returns(
      ["", "", SystemExit.new(0)]
    )
    assert(deploy.validate_definition(kubectl))
    assert_empty(deploy.validation_error_msg)
  end

  def test_validation_with_number_rollout_annotation_deprecated
    deploy = build_synced_deployment(
      template: build_deployment_template(rollout: '10', use_deprecated: true),
      replica_sets: []
    )
    kubectl.expects(:run).with('apply', '-f', anything, '--dry-run', '--output=name', anything).returns(
      ["", "super failed", SystemExit.new(1)]
    )

    refute(deploy.validate_definition(kubectl))
    expected = <<~STRING.strip
      super failed
      '#{KubernetesDeploy::Deployment::REQUIRED_ROLLOUT_ANNOTATION_DEPRECATED}: 10' is invalid. Acceptable values: #{KubernetesDeploy::Deployment::REQUIRED_ROLLOUT_TYPES.join(', ')}
    STRING
    assert_equal(expected, deploy.validation_error_msg)
  end

  def test_validation_with_number_rollout_annotation
    deploy = build_synced_deployment(template: build_deployment_template(rollout: '10'), replica_sets: [])
    kubectl.expects(:run).with('apply', '-f', anything, '--dry-run', '--output=name', anything).returns(
      ["", "super failed", SystemExit.new(1)]
    )

    refute(deploy.validate_definition(kubectl))
    expected = <<~STRING.strip
      super failed
      '#{KubernetesDeploy::Deployment::REQUIRED_ROLLOUT_ANNOTATION}: 10' is invalid. Acceptable values: #{KubernetesDeploy::Deployment::REQUIRED_ROLLOUT_TYPES.join(', ')}
    STRING
    assert_equal(expected, deploy.validation_error_msg)
  end

  def test_validation_fails_with_invalid_mix_of_annotation_deprecated
    deploy = build_synced_deployment(
      template: build_deployment_template(rollout: 'maxUnavailable', strategy: 'Recreate', use_deprecated: true),
      replica_sets: [build_rs_template]
    )
    kubectl.expects(:run).with('apply', '-f', anything, '--dry-run', '--output=name', anything).returns(
      ["", "super failed", SystemExit.new(1)]
    )
    refute(deploy.validate_definition(kubectl))

    expected = <<~STRING.strip
      super failed
      '#{KubernetesDeploy::Deployment::REQUIRED_ROLLOUT_ANNOTATION_DEPRECATED}: maxUnavailable' is incompatible with strategy 'Recreate'
    STRING
    assert_equal(expected, deploy.validation_error_msg)
  end

  def test_validation_fails_with_invalid_mix_of_annotation
    deploy = build_synced_deployment(
      template: build_deployment_template(rollout: 'maxUnavailable', strategy: 'Recreate'),
      replica_sets: [build_rs_template]
    )
    kubectl.expects(:run).with('apply', '-f', anything, '--dry-run', '--output=name', anything).returns(
      ["", "super failed", SystemExit.new(1)]
    )
    refute(deploy.validate_definition(kubectl))

    expected = <<~STRING.strip
      super failed
      '#{KubernetesDeploy::Deployment::REQUIRED_ROLLOUT_ANNOTATION}: maxUnavailable' is incompatible with strategy 'Recreate'
    STRING
    assert_equal(expected, deploy.validation_error_msg)
  end

  def test_validation_works_with_no_strategy_and_max_unavailable_annotation
    deploy = build_synced_deployment(
      template: build_deployment_template(rollout: 'maxUnavailable', strategy: nil),
      replica_sets: [build_rs_template]
    )
    kubectl.expects(:run).with('apply', '-f', anything, '--dry-run', '--output=name', anything).returns(
      ["", "", SystemExit.new(0)]
    )
    assert(deploy.validate_definition(kubectl))
  end

  def test_deploy_succeeded_not_fooled_by_stale_status_data
    deployment_status = {
      "replicas" => 3,
      "updatedReplicas" => 3, # stale -- hasn't been updated since deploy
      "unavailableReplicas" => 0,
      "availableReplicas" => 3,
      "observedGeneration" => 1, # stale
    }

    rs_status = { # points to old RS, new one not created yet
      "replicas" => 3,
      "availableReplicas" => 3,
      "readyReplicas" => 3,
      "observedGeneration" => 1,
    }
    deploy = build_synced_deployment(
      template: build_deployment_template(status: deployment_status, rollout: 'full', max_unavailable: 1),
      replica_sets: [build_rs_template(status: rs_status)],
      expect_pod_get: false
    )
    refute_predicate(deploy, :deploy_succeeded?)
  end

  def test_deploy_failed_ensures_controller_has_observed_deploy
    deploy = build_synced_deployment(
      template: build_deployment_template(status: { "observedGeneration" => 1 }, rollout: 'full', max_unavailable: 1),
      replica_sets: [build_rs_template]
    )
    KubernetesDeploy::ReplicaSet.any_instance.stubs(:pods).returns([stub(deploy_failed?: true)])
    refute_predicate(deploy, :deploy_failed?)
  end

  def test_deploy_timed_out_with_hard_timeout
    Timecop.freeze do
      deploy = build_synced_deployment(
        template: build_deployment_template(status: { "replicas" => 3, "conditions" => [] }),
        replica_sets: [build_rs_template(status: { "replica" => 1 })]
      )

      deploy.deploy_started_at = Time.now.utc - KubernetesDeploy::Deployment::TIMEOUT
      refute deploy.deploy_timed_out?

      deploy.deploy_started_at = Time.now.utc - KubernetesDeploy::Deployment::TIMEOUT - 1
      assert deploy.deploy_timed_out?
      assert_equal "Timeout reason: hard deadline for Deployment\nLatest ReplicaSet: web-1",
        deploy.timeout_message.strip
    end
  end

  def test_deploy_timed_out_based_on_progress_deadline
    Timecop.freeze do
      deployment_status = {
        "replicas" => 3,
        "observedGeneration" => 2,
        "conditions" => [{
          "type" => "Progressing",
          "status" => 'False',
          "lastUpdateTime" => Time.now.utc - 10.seconds,
          "reason" => "ProgressDeadlineExceeded",
        }],
      }
      deploy = build_synced_deployment(
        template: build_deployment_template(status: deployment_status),
        replica_sets: [build_rs_template(status: { "replica" => 1 })]
      )
      refute deploy.deploy_timed_out?, "Deploy not started shouldn't have timed out"

      deploy.deploy_started_at = Time.now.utc - 3.minutes
      assert deploy.deploy_timed_out?
      assert_equal "Timeout reason: ProgressDeadlineExceeded\nLatest ReplicaSet: web-1", deploy.timeout_message.strip
    end
  end

  def test_deploy_timed_out_based_on_timeout_override
    Timecop.freeze do
      template = build_deployment_template(
        status: {
          "replicas" => 3,
          "observedGeneration" => 2,
          "conditions" => [{
            "type" => "Progressing",
            "status" => 'False',
            "lastUpdateTime" => Time.now.utc - 10.seconds,
            "reason" => "ProgressDeadlineExceeded",
          }],
        }
      )
      template["metadata"]["annotations"][KubernetesDeploy::KubernetesResource::TIMEOUT_OVERRIDE_ANNOTATION] = "15S"
      template["spec"]["progressDeadlineSeconds"] = "10"
      deploy = build_synced_deployment(
        template: template,
        replica_sets: [build_rs_template(status: { "replica" => 1 })]
      )

      assert_equal(deploy.timeout, 15)
      refute(deploy.deploy_timed_out?, "Deploy not started shouldn't have timed out")
      deploy.deploy_started_at = Time.now.utc - 11.seconds
      refute(deploy.deploy_timed_out?, "Deploy should not timeout based on progressDeadlineSeconds")
      deploy.deploy_started_at = Time.now.utc - 16.seconds
      assert(deploy.deploy_timed_out?, "Deploy should timeout according to timoeout override")
      assert_equal(KubernetesDeploy::KubernetesResource::STANDARD_TIMEOUT_MESSAGE + "\nLatest ReplicaSet: web-1",
        deploy.timeout_message.strip)
      assert_equal(deploy.pretty_timeout_type, "timeout override: 15s")
    end
  end

  def test_deploy_timed_out_based_on_progress_deadline_ignores_statuses_for_older_generations
    Timecop.freeze do
      deployment_status = {
        "replicas" => 3,
        "observedGeneration" => 1, # current generation is 2
        "conditions" => [{
          "type" => "Progressing",
          "status" => 'False',
          "lastUpdateTime" => Time.now.utc - 10.seconds,
          "reason" => "ProgressDeadlineExceeded",
        }],
      }
      deploy = build_synced_deployment(
        template: build_deployment_template(status: deployment_status),
        replica_sets: [build_rs_template(status: { "replica" => 1 })]
      )

      deploy.deploy_started_at = Time.now.utc - 20.seconds
      refute deploy.deploy_timed_out?
    end
  end

  private

  def build_deployment_template(status: { 'replicas' => 3 }, rollout: nil,
    strategy: 'rollingUpdate', max_unavailable: nil, use_deprecated: false)

    required_rollout_annotation = if use_deprecated
      KubernetesDeploy::Deployment::REQUIRED_ROLLOUT_ANNOTATION_DEPRECATED
    else
      KubernetesDeploy::Deployment::REQUIRED_ROLLOUT_ANNOTATION
    end

    base_deployment_manifest = fixtures.find { |fixture| fixture["kind"] == "Deployment" }
    result = base_deployment_manifest.deep_merge("status" => status)
    result["metadata"]["annotations"][required_rollout_annotation] = rollout if rollout

    if (spec_override = status["replicas"].presence) # ignores possibility of surge; need a spec_replicas arg for that
      result["spec"]["replicas"] = spec_override
    end

    if strategy == "Recreate"
      result["spec"]["strategy"] = { "type" => strategy }
    end

    if strategy.nil?
      result["spec"]["strategy"] = nil
    end

    if max_unavailable
      result["spec"]["strategy"]["rollingUpdate"] = { "maxUnavailable" => max_unavailable }
    end

    result
  end

  def build_rs_template(status: { 'replicas' => 3 })
    base_rs_manifest = fixtures.find { |fixture| fixture["kind"] == "ReplicaSet" }
    result = base_rs_manifest.deep_merge("status" => status)

    if (spec_override = status["replicas"].presence) # ignores possibility of surge; need a spec_replicas arg for that
      result["spec"]["replicas"] = spec_override
    end
    result
  end

  def build_synced_deployment(template:, replica_sets:, expect_pod_get: nil)
    deploy = KubernetesDeploy::Deployment.new(namespace: "test", context: "nope", logger: logger, definition: template)
    stub_kind_get("Deployment", items: [template])
    stub_kind_get("ReplicaSet", items: replica_sets)

    expect_pod_get = replica_sets.present? if expect_pod_get.nil?
    if expect_pod_get
      stub_kind_get("Pod", items: [])
    end

    deploy.sync(build_resource_cache)
    deploy
  end

  def kubectl
    @kubectl ||= build_runless_kubectl
  end

  def fixtures
    @fixtures ||= YAML.load_stream(File.read(File.join(fixture_path('for_unit_tests'), 'deployment_test.yml')))
  end
end
