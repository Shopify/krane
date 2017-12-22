# frozen_string_literal: true
require 'test_helper'

class PodTest < KubernetesDeploy::TestCase
  def test_deploy_failed_is_true_for_missing_image_error
    container_state = {
      "state" => {
        "waiting" => {
          "message" => "rpc error: code = 2 desc = Error: image library/some-invalid-image not found",
          "reason" => "ImagePullBackOff"
        }
      }
    }
    pod = build_synced_pod(build_pod_template(container_state: container_state))
    assert pod.deploy_failed?

    expected_msg = <<~STRING
      The following containers encountered errors:
      > hello-cloud: Failed to pull image busybox. Did you wait for it to be built and pushed to the registry before deploying?
    STRING
    assert_equal expected_msg, pod.failure_message
  end

  def test_deploy_failed_is_true_for_missing_tag_error
    message = "rpc error: code = 2 desc = Tag thisImageIsBad not found in repository docker.io/library/hello-world"
    container_state = {
      "state" => {
        "waiting" => {
          "message" => message,
          "reason" => "ErrImagePull"
        }
      }
    }
    pod = build_synced_pod(build_pod_template(container_state: container_state))
    assert pod.deploy_failed?

    expected_msg = <<~STRING
      The following containers encountered errors:
      > hello-cloud: Failed to pull image busybox. Did you wait for it to be built and pushed to the registry before deploying?
    STRING
    assert_equal expected_msg, pod.failure_message
  end

  def test_deploy_failed_is_false_for_intermittent_image_error
    container_state = {
      "state" => {
        "waiting" => {
          "message" => "Failed to pull image 'gcr.io/*': rpc error: code = 2 desc = net/http: request canceled",
          "reason" => "ImagePullBackOff"
        }
      }
    }
    pod = build_synced_pod(build_pod_template(container_state: container_state))

    refute pod.deploy_failed?
    assert_nil pod.failure_message
  end

  def test_deploy_failed_is_true_for_image_pull_backoff
    container_state = {
      "state" => {
        "waiting" => {
          "message" => "Back-off pulling image 'docker.io/library/hello-world'",
          "reason" => "ImagePullBackOff"
        }
      }
    }
    pod = build_synced_pod(build_pod_template(container_state: container_state))

    assert pod.deploy_failed?
    expected_msg = <<~STRING
      The following containers encountered errors:
      > hello-cloud: Failed to pull image busybox. Did you wait for it to be built and pushed to the registry before deploying?
    STRING
    assert_equal expected_msg, pod.failure_message
  end

  def test_deploy_failed_is_true_for_container_config_error_post_18
    container_state = {
      "state" => {
        "waiting" => {
          "message" => "The reason it failed",
          "reason" => "CreateContainerConfigError"
        }
      }
    }
    pod = build_synced_pod(build_pod_template(container_state: container_state))

    assert pod.deploy_failed?
    expected_msg = <<~STRING
      The following containers encountered errors:
      > hello-cloud: Failed to generate container configuration: The reason it failed
    STRING
    assert_equal expected_msg, pod.failure_message
  end

  def test_deploy_failed_is_true_for_container_config_error_pre_18
    container_state = {
      "state" => {
        "waiting" => {
          "message" => "Generate Container Config Failed",
          "reason" => "The reason it failed"
        }
      }
    }
    pod = build_synced_pod(build_pod_template(container_state: container_state))

    assert pod.deploy_failed?
    expected_msg = <<~STRING
      The following containers encountered errors:
      > hello-cloud: Failed to generate container configuration: The reason it failed
    STRING
    assert_equal expected_msg, pod.failure_message
  end

  def test_deploy_failed_is_true_for_crash_loop_backoffs
    container_state = {
      "lastState" => {
        "terminated" => { "exitCode" => 1 }
      },
      "state" => {
        "waiting" => {
          "message" => "Back-off 10s restarting failed container=init-crash-loop-back-off pod=init-crash-74b6dfcdc5",
          "reason" => "CrashLoopBackOff"
        }
      }
    }
    pod = build_synced_pod(build_pod_template(container_state: container_state))

    assert pod.deploy_failed?
    expected_msg = <<~STRING
      The following containers encountered errors:
      > hello-cloud: Crashing repeatedly (exit 1). See logs for more information.
    STRING
    assert_equal expected_msg, pod.failure_message
  end

  def test_deploy_failed_is_true_for_container_cannot_run_error
    container_state = {
      "state" => {
        "terminated" => {
          "message" => "/not/a/command: no such file or directory",
          "reason" => "ContainerCannotRun",
          "exitCode" => 127
        }
      }
    }
    pod = build_synced_pod(build_pod_template(container_state: container_state))

    assert pod.deploy_failed?
    expected_msg = <<~STRING
      The following containers encountered errors:
      > hello-cloud: Failed to start (exit 127): /not/a/command: no such file or directory
    STRING
    assert_equal expected_msg, pod.failure_message
  end

  private

  def pod_spec
    @pod_spec ||= YAML.load_file(File.join(fixture_path('for_unit_tests'), 'pod_test.yml'))
  end

  def build_synced_pod(template)
    pod = KubernetesDeploy::Pod.new(namespace: 'test', context: 'nope', definition: template,
      logger: @logger, deploy_started_at: Time.now.utc)
    pod.sync(template)
    pod
  end

  def build_pod_template(container_state:)
    pod_spec.merge(
      "status" => {
        "phase" => "Pending",
        "containerStatuses" => [
          {
            "lastState" => {},
            "state" => {},
            "name" => "hello-cloud",
            "ready" => false,
            "restartCount" => 0
          }.merge(container_state)
        ]
      }
    )
  end
end
