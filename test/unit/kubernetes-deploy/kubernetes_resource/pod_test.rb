# frozen_string_literal: true
require 'test_helper'

class PodTest < KubernetesDeploy::TestCase
  include ResourceCacheTestHelper

  def test_deploy_failed_is_true_for_missing_image_error
    container_state = {
      "state" => {
        "waiting" => {
          "message" => "rpc error: code = 2 desc = Error: image library/some-invalid-image not found",
          "reason" => "ErrImagePull",
        },
      },
    }
    pod = build_synced_pod(build_pod_template(container_state: container_state))
    assert(pod.deploy_failed?)

    expected_msg = <<~STRING
      The following containers encountered errors:
      > hello-cloud: Failed to pull image busybox. Did you wait for it to be built and pushed to the registry before deploying?
    STRING
    assert_equal(expected_msg.strip, pod.failure_message)
  end

  def test_deploy_failed_is_true_for_missing_tag_error
    message = "rpc error: code = 2 desc = Tag thisImageIsBad not found in repository docker.io/library/hello-world"
    container_state = {
      "state" => {
        "waiting" => {
          "message" => message,
          "reason" => "ErrImagePull",
        },
      },
    }
    pod = build_synced_pod(build_pod_template(container_state: container_state))
    assert(pod.deploy_failed?)

    expected_msg = <<~STRING
      The following containers encountered errors:
      > hello-cloud: Failed to pull image busybox. Did you wait for it to be built and pushed to the registry before deploying?
    STRING
    assert_equal(expected_msg.strip, pod.failure_message)
  end

  def test_deploy_failed_is_false_for_intermittent_image_error
    container_state = {
      "state" => {
        "waiting" => {
          "message" => "Failed to pull image 'gcr.io/*': rpc error: code = 2 desc = net/http: request canceled",
          "reason" => "ErrImagePull",
        },
      },
    }
    pod = build_synced_pod(build_pod_template(container_state: container_state))

    refute(pod.deploy_failed?)
    assert_nil(pod.failure_message)
  end

  def test_deploy_failed_is_false_for_image_pull_backoff
    # Backoffs start quickly enough that failing eagerly on this basis alone (without further error details)
    # leads to many incorrect failure judgements at scale
    container_state = {
      "state" => {
        "waiting" => {
          "message" => "Back-off pulling image 'docker.io/library/hello-world'",
          "reason" => "ImagePullBackOff",
        },
      },
    }
    pod = build_synced_pod(build_pod_template(container_state: container_state))

    refute(pod.deploy_failed?)
    assert_nil(pod.failure_message)
  end

  def test_deploy_failed_is_true_for_container_config_error_post_18
    container_state = {
      "state" => {
        "waiting" => {
          "message" => "The reason it failed",
          "reason" => "CreateContainerConfigError",
        },
      },
    }
    pod = build_synced_pod(build_pod_template(container_state: container_state))

    assert(pod.deploy_failed?)
    expected_msg = <<~STRING
      The following containers encountered errors:
      > hello-cloud: Failed to generate container configuration: The reason it failed
    STRING
    assert_equal(expected_msg.strip, pod.failure_message)
  end

  def test_deploy_failed_is_true_for_crash_loop_backoffs
    container_state = {
      "lastState" => {
        "terminated" => { "exitCode" => 1 },
      },
      "state" => {
        "waiting" => {
          "message" => "Back-off 10s restarting failed container=init-crash-loop-back-off pod=init-crash-74b6dfcdc5",
          "reason" => "CrashLoopBackOff",
        },
      },
    }
    pod = build_synced_pod(build_pod_template(container_state: container_state))

    assert(pod.deploy_failed?)
    expected_msg = <<~STRING
      The following containers encountered errors:
      > hello-cloud: Crashing repeatedly (exit 1). See logs for more information.
    STRING
    assert_equal(expected_msg.strip, pod.failure_message)
  end

  def test_deploy_failed_is_true_for_container_cannot_run_error
    container_state = {
      "state" => {
        "terminated" => {
          "message" => "/not/a/command: no such file or directory",
          "reason" => "ContainerCannotRun",
          "exitCode" => 127,
        },
      },
    }
    pod = build_synced_pod(build_pod_template(container_state: container_state))

    assert(pod.deploy_failed?)
    expected_msg = <<~STRING
      The following containers encountered errors:
      > hello-cloud: Failed to start (exit 127): /not/a/command: no such file or directory
    STRING
    assert_equal(expected_msg.strip, pod.failure_message)
  end

  def test_deploy_failed_is_true_for_evicted_unmanaged_pods
    template = pod_spec.merge(
      "status" => {
        "message" => "The node was low on resource: nodefsInodes.",
        "phase" => "Failed",
        "reason" => "Evicted",
        "startTime" => "2018-04-13T22:43:23Z",
      }
    )
    pod = build_synced_pod(template)

    assert_predicate(pod, :deploy_failed?)
    assert_equal("Pod status: Failed (Reason: Evicted).", pod.failure_message)
  end

  def test_deploy_failed_is_false_for_evicted_managed_pods
    template = pod_spec.merge(
      "status" => {
        "message" => "The node was low on resource: nodefsInodes.",
        "phase" => "Failed",
        "reason" => "Evicted",
        "startTime" => "2018-04-13T22:43:23Z",
      }
    )
    pod = build_synced_pod(template, parent: mock)

    refute_predicate(pod, :deploy_failed?)
    assert_nil(pod.failure_message)
  end

  def test_deploy_failed_is_true_for_preempted_unmanaged_pods
    template = pod_spec.merge(
      "status" => {
        "message" => "Preempted in order to admit critical pod",
        "phase" => "Failed",
        "reason" => "Preempting",
        "startTime" => "2018-04-13T22:43:23Z",
      }
    )
    pod = build_synced_pod(template)

    assert_predicate(pod, :deploy_failed?)
    assert_equal("Pod status: Failed (Reason: Preempting).", pod.failure_message)
  end

  def test_deploy_failed_is_false_for_preempted_managed_pods
    template = pod_spec.merge(
      "status" => {
        "message" => "Preempted in order to admit critical pod",
        "phase" => "Failed",
        "reason" => "Preempting",
        "startTime" => "2018-04-13T22:43:23Z",
      }
    )
    pod = build_synced_pod(template, parent: mock)

    refute_predicate(pod, :deploy_failed?)
    assert_nil(pod.failure_message)
  end

  def test_deploy_failed_is_true_for_terminating_unmanaged_pods
    template = build_pod_template
    template["metadata"]["deletionTimestamp"] = "2018-04-13T22:43:23Z"
    pod = build_synced_pod(template)

    assert_predicate(pod, :terminating?)
    assert_predicate(pod, :deploy_failed?)
    assert_equal("Pod status: Terminating.", pod.failure_message)
  end

  def test_deploy_failed_is_false_for_terminating_managed_pods
    template = build_pod_template
    template["metadata"]["deletionTimestamp"] = "2018-04-13T22:43:23Z"
    pod = build_synced_pod(template, parent: mock)

    assert_predicate(pod, :terminating?)
    refute_predicate(pod, :deploy_failed?)
    assert_nil(pod.failure_message)
  end

  def test_deploy_failed_is_true_for_disappeared_unmanaged_pods
    template = build_pod_template
    pod = KubernetesDeploy::Pod.new(namespace: 'test', context: 'nope', definition: template,
      logger: @logger, deploy_started_at: Time.now.utc)
    cache = build_resource_cache
    cache.expects(:get_instance).raises(KubernetesDeploy::Kubectl::ResourceNotFoundError)
    pod.sync(cache)

    assert_predicate(pod, :disappeared?)
    assert_predicate(pod, :deploy_failed?)
    assert_equal("Pod status: Disappeared.", pod.failure_message)
  end

  def test_deploy_failed_is_false_for_disappeared_managed_pods
    template = build_pod_template
    pod = KubernetesDeploy::Pod.new(namespace: 'test', context: 'nope', definition: template,
      logger: @logger, deploy_started_at: Time.now.utc, parent: mock)
    cache = build_resource_cache
    cache.expects(:get_instance).raises(KubernetesDeploy::Kubectl::ResourceNotFoundError)
    pod.sync(cache)

    assert_predicate(pod, :disappeared?)
    refute_predicate(pod, :deploy_failed?)
    assert_nil(pod.failure_message)
  end

  private

  def pod_spec
    @pod_spec ||= YAML.load_file(File.join(fixture_path('for_unit_tests'), 'pod_test.yml'))
  end

  def build_synced_pod(template, parent: nil)
    pod = KubernetesDeploy::Pod.new(namespace: 'test', context: 'nope', definition: template,
      logger: @logger, deploy_started_at: Time.now.utc, parent: parent)
    stub_kind_get("Pod", items: [template])
    KubernetesDeploy::ContainerLogs.any_instance.stubs(:sync) unless parent.present?
    pod.sync(build_resource_cache)
    pod
  end

  def build_pod_template(container_state: {})
    pod_spec.merge(
      "status" => {
        "phase" => "Pending",
        "containerStatuses" => [
          {
            "lastState" => {},
            "state" => {},
            "name" => "hello-cloud",
            "ready" => false,
            "restartCount" => 0,
          }.merge(container_state),
        ],
      }
    )
  end
end
