# frozen_string_literal: true
require 'test_helper'

class PodTest < KubernetesDeploy::TestCase
  def test_deploy_failed_is_true_for_missing_image_error
    pod = build_pod(pod_spec)
    fake_status = fake_status_with_container_state(
      "state" => {
        "waiting" => {
          "message" => "rpc error: code = 2 desc = Error: image library/some-invalid-image not found",
          "reason" => "ImagePullBackOff"
        }
      }
    )

    fake_pod_data = pod_spec.merge(fake_status)
    pod.sync(fake_pod_data)
    assert pod.deploy_failed?

    expected_msg = <<~STRING
      The following containers encountered errors:
      > hello-cloud: Failed to pull image busybox. Did you wait for it to be built and pushed to the registry before deploying?
    STRING
    assert_equal expected_msg, pod.failure_message
  end

  def test_deploy_failed_is_true_for_missing_tag_error
    pod = build_pod(pod_spec)
    message = "rpc error: code = 2 desc = Tag thisImageIsBad not found in repository docker.io/library/hello-world"
    fake_status = fake_status_with_container_state(
      "state" => {
        "waiting" => {
          "message" => message,
          "reason" => "ErrImagePull"
        }
      }
    )

    fake_pod_data = pod_spec.merge(fake_status)
    pod.sync(fake_pod_data)
    assert pod.deploy_failed?

    expected_msg = <<~STRING
      The following containers encountered errors:
      > hello-cloud: Failed to pull image busybox. Did you wait for it to be built and pushed to the registry before deploying?
    STRING
    assert_equal expected_msg, pod.failure_message
  end

  def test_deploy_failed_is_false_for_intermittent_image_error
    pod = build_pod(pod_spec)
    fake_status = fake_status_with_container_state(
      "state" => {
        "waiting" => {
          "message" => "Failed to pull image 'gcr.io/*': rpc error: code = 2 desc = net/http: request canceled",
          "reason" => "ImagePullBackOff"
        }
      }
    )

    fake_pod_data = pod_spec.merge(fake_status)
    pod.sync(fake_pod_data)
    refute pod.deploy_failed?
    assert_nil pod.failure_message
  end

  def test_deploy_failed_is_true_for_image_pull_backoff
    pod = build_pod(pod_spec)
    fake_status = fake_status_with_container_state(
      "state" => {
        "waiting" => {
          "message" => "Back-off pulling image 'docker.io/library/hello-world'",
          "reason" => "ImagePullBackOff"
        }
      }
    )

    fake_pod_data = pod_spec.merge(fake_status)
    pod.sync(fake_pod_data)
    assert pod.deploy_failed?

    expected_msg = <<~STRING
      The following containers encountered errors:
      > hello-cloud: Failed to pull image busybox. Did you wait for it to be built and pushed to the registry before deploying?
    STRING
    assert_equal expected_msg, pod.failure_message
  end

  private

  def pod_spec
    @pod_spec ||= YAML.load_file(File.join(fixture_path('hello-cloud'), 'unmanaged-pod.yml.erb'))
  end

  def fake_status_with_container_state(state)
    {
      "status" => {
        "phase" => "Pending",
        "containerStatuses" => [
          {
            "lastState" => {},
            "name" => "hello-cloud",
            "ready" => false,
            "restartCount" => 0
          }.merge(state)
        ]
      }
    }
  end

  def build_pod(spec)
    KubernetesDeploy::Pod.new(
      namespace: 'test',
      context: 'minikube',
      definition: spec,
      logger: @logger,
      deploy_started_at: Time.now.utc
    )
  end
end
