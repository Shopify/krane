# frozen_string_literal: true
require 'test_helper'

class DeploymentTest < KubernetesDeploy::TestCase
  def setup
    KubernetesDeploy::Kubectl.any_instance.expects(:run).never
    super
  end

  def test_deploy_succeeded_with_none_annotation
    deployment_status = {
      "replicas" => 3,
      "updatedReplicas" => 1,
      "unavailableReplicas" => 1,
      "availableReplicas" => 0
    }

    rs_status = {
      "replicas" => 3,
      "availableReplicas" => 0,
      "readyReplicas" => 0
    }
    dep_template = build_deployment_template(status: deployment_status, rollout: 'none',
      strategy: 'RollingUpdate', max_unavailable: 1)
    deploy = build_synced_deployment(template: dep_template, replica_sets: [build_rs_template(status: rs_status)])
    assert deploy.deploy_succeeded?
  end

  def test_deploy_succeeded_is_false_with_none_annotation_before_new_rs_created
    deployment_status = {
      "replicas" => 3,
      "updatedReplicas" => 3,
      "unavailableReplicas" => 0,
      "availableReplicas" => 3
    }
    deploy = build_synced_deployment(
      template: build_deployment_template(status: deployment_status, rollout: 'none'),
      replica_sets: []
    )
    refute deploy.deploy_succeeded?
  end

  def test_deploy_succeeded_with_max_unavailable
    deployment_status = {
      "replicas" => 3, # one terminating in old rs, one starting in new rs, one up in new rs
      "updatedReplicas" => 2,
      "unavailableReplicas" => 2,
      "availableReplicas" => 1
    }

    rs_status = {
      "replicas" => 2,
      "availableReplicas" => 1,
      "readyReplicas" => 1
    }
    replica_sets = [build_rs_template(status: rs_status)]

    deploy = build_synced_deployment(
      template: build_deployment_template(status: deployment_status, rollout: 'maxUnavailable', max_unavailable: 3),
      replica_sets: replica_sets
    )
    assert deploy.deploy_succeeded?

    deploy = build_synced_deployment(
      template: build_deployment_template(status: deployment_status, rollout: 'maxUnavailable', max_unavailable: 2),
      replica_sets: replica_sets
    )
    assert deploy.deploy_succeeded?

    deploy = build_synced_deployment(
      template: build_deployment_template(status: deployment_status, rollout: 'maxUnavailable', max_unavailable: 1),
      replica_sets: replica_sets
    )
    refute deploy.deploy_succeeded?

    deploy = build_synced_deployment(
      template: build_deployment_template(status: deployment_status, rollout: 'maxUnavailable', max_unavailable: 0),
      replica_sets: replica_sets
    )
    refute deploy.deploy_succeeded?
  end

  def test_deploy_succeeded_with_max_unavailable_as_percent
    deployment_status = {
      "replicas" => 3,
      "updatedReplicas" => 2,
      "unavailableReplicas" => 2,
      "availableReplicas" => 1
    }

    rs_status = {
      "replicas" => 2,
      "availableReplicas" => 1,
      "readyReplicas" => 1
    }
    replica_sets = [build_rs_template(status: rs_status)]

    dep_template = build_deployment_template(status: deployment_status,
      rollout: 'maxUnavailable', max_unavailable: '100%')
    deploy = build_synced_deployment(template: dep_template, replica_sets: replica_sets)
    assert deploy.deploy_succeeded?

    # rounds up to two max
    deploy = build_synced_deployment(
      template: build_deployment_template(status: deployment_status, rollout: 'maxUnavailable', max_unavailable: '67%'),
      replica_sets: replica_sets
    )
    assert deploy.deploy_succeeded?

    # rounds down to one max
    deploy = build_synced_deployment(
      template: build_deployment_template(status: deployment_status, rollout: 'maxUnavailable', max_unavailable: '66%'),
      replica_sets: replica_sets
    )
    refute deploy.deploy_succeeded?

    deploy = build_synced_deployment(
      template: build_deployment_template(status: deployment_status, rollout: 'maxUnavailable', max_unavailable: '0%'),
      replica_sets: replica_sets
    )
    refute deploy.deploy_succeeded?
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

  def test_validation_fails_with_invalid_rollout_annotation
    deploy = build_synced_deployment(template: build_deployment_template(rollout: 'bad'), replica_sets: [])
    deploy.kubectl.expects(:run).with('create', '-f', anything, '--dry-run', '--output=name', anything).returns(
      ["", "super failed", SystemExit.new(1)]
    )
    refute deploy.validate_definition

    expected = <<~STRING.strip
      super failed
      '#{KubernetesDeploy::Deployment::REQUIRED_ROLLOUT_ANNOTATION}: bad' is invalid. Acceptable values: #{KubernetesDeploy::Deployment::REQUIRED_ROLLOUT_TYPES.join(', ')}
    STRING
    assert_equal expected, deploy.validation_error_msg
  end

  def test_validation_fails_with_invalid_mix_of_annotation
    deploy = build_synced_deployment(
      template: build_deployment_template(rollout: 'maxUnavailable', strategy: 'Recreate'),
      replica_sets: [build_rs_template]
    )
    deploy.kubectl.expects(:run).with('create', '-f', anything, '--dry-run', '--output=name', anything).returns(
      ["", "super failed", SystemExit.new(1)]
    )
    refute deploy.validate_definition

    expected = <<~STRING.strip
      super failed
      '#{KubernetesDeploy::Deployment::REQUIRED_ROLLOUT_ANNOTATION}: maxUnavailable' is incompatible with strategy 'Recreate'
    STRING
    assert_equal expected, deploy.validation_error_msg
  end

  def test_deploy_succeeded_not_fooled_by_stale_rs_data_in_deploy_status
    deployment_status = {
      "replicas" => 3,
      "updatedReplicas" => 3, # stale -- hasn't been updated since new RS was created
      "unavailableReplicas" => 0,
      "availableReplicas" => 3
    }

    rs_status = {
      "replicas" => 1,
      "availableReplicas" => 0,
      "readyReplicas" => 0
    }
    deploy = build_synced_deployment(
      template: build_deployment_template(status: deployment_status, rollout: 'full', max_unavailable: 1),
      replica_sets: [build_rs_template(status: rs_status)]
    )
    refute deploy.deploy_succeeded?
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
        "conditions" => [{
          "type" => "Progressing",
          "status" => 'False',
          "lastUpdateTime" => Time.now.utc - 10.seconds,
          "reason" => "Failed to progress"
        }]
      }
      deploy = build_synced_deployment(
        template: build_deployment_template(status: deployment_status),
        replica_sets: [build_rs_template(status: { "replica" => 1 })]
      )
      deploy.deploy_started_at = Time.now.utc - 3.minutes
      deploy.kubectl.expects(:server_version).returns(Gem::Version.new("1.8"))

      assert deploy.deploy_timed_out?
      assert_equal "Timeout reason: Failed to progress\nLatest ReplicaSet: web-1", deploy.timeout_message.strip
    end
  end

  def test_deploy_timed_out_based_on_progress_deadline_ignores_conditions_older_than_the_deploy
    Timecop.freeze do
      deployment_status = {
        "replicas" => 3,
        "conditions" => [{
          "type" => "Progressing",
          "status" => 'False',
          "lastUpdateTime" => Time.now.utc - 10.seconds,
          "reason" => "Failed to progress"
        }]
      }
      deploy = build_synced_deployment(
        template: build_deployment_template(status: deployment_status),
        replica_sets: [build_rs_template(status: { "replica" => 1 })]
      )
      deploy.kubectl.expects(:server_version).returns(Gem::Version.new("1.8")).at_least_once

      deploy.deploy_started_at = nil # not started yet
      refute deploy.deploy_timed_out?

      deploy.deploy_started_at = Time.now.utc - 4.seconds # 10s ago is before deploy started
      refute deploy.deploy_timed_out?

      deploy.deploy_started_at = Time.now.utc - 5.seconds # 10s ago is "equal" to deploy time (fudge for clock skew)
      assert deploy.deploy_timed_out?
    end
  end

  def test_deploy_timed_out_based_on_progress_deadline_accommodates_stale_conditions_bug_in_k8s_176_and_lower
    Timecop.freeze do
      deployment_status = {
        "replicas" => 3,
        "conditions" => [{
          "type" => "Progressing",
          "status" => 'False',
          "lastUpdateTime" => Time.now.utc - 5.seconds,
          "reason" => "Failed to progress"
        }]
      }
      deploy = build_synced_deployment(
        template: build_deployment_template(status: deployment_status),
        replica_sets: [build_rs_template(status: { "replica" => 1 })]
      )
      deploy.deploy_started_at = Time.now.utc - 5.seconds # progress deadline of 10s has not elapsed
      deploy.kubectl.expects(:server_version).returns(Gem::Version.new("1.7.6"))

      refute deploy.deploy_timed_out?
    end
  end

  private

  def build_deployment_template(status: { 'replicas' => 3 }, rollout: nil,
    strategy: 'rollingUpdate', max_unavailable: nil)

    base_deployment_manifest = fixtures.find { |fixture| fixture["kind"] == "Deployment" }
    result = base_deployment_manifest.deep_merge("status" => status)
    result["metadata"]["annotations"][KubernetesDeploy::Deployment::REQUIRED_ROLLOUT_ANNOTATION] = rollout if rollout

    if spec_override = status["replicas"].presence # ignores possibility of surge; need a spec_replicas arg for that
      result["spec"]["replicas"] = spec_override
    end

    if strategy == "Recreate"
      result["spec"]["strategy"] = { "type" => strategy }
    end

    if max_unavailable
      result["spec"]["strategy"]["rollingUpdate"] = { "maxUnavailable" => max_unavailable }
    end

    result
  end

  def build_rs_template(status: { 'replicas' => 3 })
    base_rs_manifest = fixtures.find { |fixture| fixture["kind"] == "ReplicaSet" }
    result = base_rs_manifest.deep_merge("status" => status)

    if spec_override = status["replicas"].presence # ignores possibility of surge; need a spec_replicas arg for that
      result["spec"]["replicas"] = spec_override
    end
    result
  end

  def build_synced_deployment(template:, replica_sets:)
    deploy = KubernetesDeploy::Deployment.new(namespace: "test", context: "nope", logger: logger, definition: template)
    deploy.kubectl.expects(:run).with("get", "Deployment", "web", "--output=json").returns(
      [template.to_json, "", SystemExit.new(0)]
    )

    if replica_sets.present?
      KubernetesDeploy::ReplicaSet.any_instance.expects(:kubectl).returns(deploy.kubectl)
      deploy.kubectl.expects(:run).with("get", "pods", "-a", "--output=json", anything).returns(
        ['{ "items": [] }', "", SystemExit.new(0)]
      )
    end

    deploy.kubectl.expects(:run).with("get", "replicasets", "--output=json", anything).returns(
      [{ "items" => replica_sets }.to_json, "", SystemExit.new(0)]
    )
    deploy.sync
    deploy
  end

  def fixtures
    @fixtures ||= YAML.load_stream(File.read(File.join(fixture_path('for_unit_tests'), 'deployment_test.yml')))
  end
end
