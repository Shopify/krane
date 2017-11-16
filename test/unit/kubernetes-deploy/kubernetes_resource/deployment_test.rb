# frozen_string_literal: true
require 'test_helper'

class DeploymentTest < KubernetesDeploy::TestCase
  def test_deploy_succeeded_with_none_annotation
    rollout = {
      'metadata' => {
        'name' => 'fake',
        'annotations' => { KubernetesDeploy::Deployment::REQUIRED_ROLLOUT_ANNOTATION => 'none' }
      }
    }

    deploy = KubernetesDeploy::Deployment.new(namespace: "", context: "", logger: logger, definition: rollout)
    deploy.instance_variable_set(:@latest_rs, true)

    assert deploy.deploy_succeeded?
  end

  def test_deploy_succeeded_with_max_unavailable
    rollout = {
      'metadata' => {
        'name' => 'fake',
        'annotations' => { KubernetesDeploy::Deployment::REQUIRED_ROLLOUT_ANNOTATION => 'maxUnavailable' }
      }
    }

    deploy = KubernetesDeploy::Deployment.new(namespace: "", context: "", logger: logger, definition: rollout)
    mock_rs = Minitest::Mock.new
    needed = 2
    mock_rs.expect :present?, true
    mock_rs.expect :desired_replicas, needed
    mock_rs.expect :ready_replicas, needed
    mock_rs.expect :available_replicas, needed
    deploy.instance_variable_set(:@max_unavailable, 0)
    deploy.instance_variable_set(:@latest_rs, mock_rs)
    deploy.instance_variable_set(:@desired_replicas, needed)

    assert deploy.deploy_succeeded?
  end

  def test_deploy_succeeded_fails_with_max_unavailable
    rollout = {
      'metadata' => {
        'name' => 'fake',
        'annotations' => { KubernetesDeploy::Deployment::REQUIRED_ROLLOUT_ANNOTATION => 'maxUnavailable' }
      }
    }

    deploy = KubernetesDeploy::Deployment.new(namespace: "", context: "", logger: logger, definition: rollout)
    mock_rs = Minitest::Mock.new
    needed = 2
    mock_rs.expect :present?, true
    mock_rs.expect :desired_replicas, needed
    mock_rs.expect :ready_replicas, needed - 1
    mock_rs.expect :available_replicas, needed - 1
    deploy.instance_variable_set(:@max_unavailable, 0)
    deploy.instance_variable_set(:@latest_rs, mock_rs)
    deploy.instance_variable_set(:@desired_replicas, needed)

    refute deploy.deploy_succeeded?
  end

  def test_deploy_succeeded_fails_with_max_unavailable_as_a_percent
    rollout = {
      'metadata' => {
        'name' => 'fake',
        'annotations' => { KubernetesDeploy::Deployment::REQUIRED_ROLLOUT_ANNOTATION => 'maxUnavailable' }
      }
    }

    deploy = KubernetesDeploy::Deployment.new(namespace: "", context: "", logger: logger, definition: rollout)
    mock_rs = Minitest::Mock.new
    needed = 2
    mock_rs.expect :present?, true
    mock_rs.expect :desired_replicas, needed
    mock_rs.expect :ready_replicas, needed - 1
    mock_rs.expect :available_replicas, needed - 1
    deploy.instance_variable_set(:@max_unavailable, '49%')
    deploy.instance_variable_set(:@latest_rs, mock_rs)
    deploy.instance_variable_set(:@desired_replicas, needed)

    refute deploy.deploy_succeeded?
  end

  def test_deploy_succeeded_raises_with_invalid_annotation
    rollout = {
      'metadata' => {
        'name' => 'fake',
        'annotations' => { KubernetesDeploy::Deployment::REQUIRED_ROLLOUT_ANNOTATION => 'invalid' }
      }
    }

    deploy = KubernetesDeploy::Deployment.new(namespace: "foo", context: "", logger: logger, definition: rollout)
    deploy.instance_variable_set(:@latest_rs, true)

    assert_raises(RuntimeError) { deploy.deploy_succeeded? }
  end

  def test_deploy_succeeded_raises_with_invalid_mix_of_annotation
    rollout = {
      'spec' => {
        'strategy' => 'recreate'
      },
      'metadata' => {
        'name' => 'fake',
        'annotations' => { KubernetesDeploy::Deployment::REQUIRED_ROLLOUT_ANNOTATION => 'maxUnavailable' }
      }
    }

    kubectl_mock = Minitest::Mock.new
    status_mock = Minitest::Mock.new
    status_mock.expect :success?, true
    kubectl_mock.expect(:run, [true, true, status_mock], [Object, Object, Object, Object, Object, Object])
    deploy = KubernetesDeploy::Deployment.new(namespace: "", context: "", logger: logger, definition: rollout)
    deploy.instance_variable_set(:@kubectl, kubectl_mock)

    refute deploy.validate_definition
  end
end
