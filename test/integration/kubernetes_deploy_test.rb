require 'test_helper'

class KubernetesDeployTest < KubernetesDeploy::IntegrationTest
  def test_full_basic_set_deploy_succeeds
    deploy_fixture_set("basic")
    basic = FixtureSetAssertions::Basic.new(@namespace)
    basic.assert_all_up
  end

  def test_partial_deploy_followed_by_full_deploy
    deploy_fixture_set("basic", subset: ["configmap-data", "redis"])
    basic = FixtureSetAssertions::Basic.new(@namespace)
    basic.assert_all_redis_resources_up
    basic.assert_configmap_data_present
    basic.refute_managed_pod_exists
    basic.refute_web_resources_exist

    deploy_fixture_set("basic")
    basic.assert_all_up
  end

  def test_pruning
    deploy_fixture_set("basic")
    basic = FixtureSetAssertions::Basic.new(@namespace)
    basic.assert_all_up

    deploy_fixture_set("basic", subset: ["redis"])
    basic.assert_all_redis_resources_up
    basic.refute_configmap_data_exists
    basic.refute_managed_pod_exists
    basic.refute_web_resources_exist
  end

  def test_pvcs_are_not_pruned
    deploy_fixture_set("basic", subset: ["redis"])
    basic = FixtureSetAssertions::Basic.new(@namespace)
    basic.assert_all_redis_resources_up

    deploy_fixture_set("basic", subset: ["configmap-data"])
    basic.assert_configmap_data_present
    basic.refute_redis_resources_exist(expect_pvc: true)
  end

  def test_success_with_unrecognized_resource_type
    # Secrets are intentionally unsupported because they should not be committed to your repo
    fixture_set = load_fixture_data("basic", ["configmap-data"])
    secret = {
      "apiVersion" => "v1",
      "kind" => "Secret",
      "metadata" => { "name" => "test" },
      "data" => { "foo" => "YmFy" }
    }
    fixture_set["secret"] = { "Secret" => secret }
    deploy_loaded_fixture_set(fixture_set)

    live_secret = kubeclient.get_secret("test", @namespace)
    assert_equal({ foo: "YmFy" }, live_secret["data"].to_h)
  end

  def test_invalid_yaml_fails_fast
    assert_raises(KubernetesDeploy::FatalDeploymentError, /Template \S+ cannot be parsed/) do
      deploy_fixture_set("invalid", subset: ["yaml-error"])
    end
  end

  def test_invalid_k8s_spec_that_is_valid_yaml_fails_fast
    fixture_set = load_fixture_data("basic", ["configmap-data"])
    configmap = fixture_set["configmap-data"]["ConfigMap"].first
    configmap["metadata"]["myKey"] = "uhOh"

    assert_raises(KubernetesDeploy::FatalDeploymentError, /Dry run failed for template configmap-data/) do
      deploy_loaded_fixture_set(fixture_set)
    end
    assert_logs_match(/error validating data\: found invalid field myKey for v1.ObjectMeta/)
  end

  def test_dead_pods_in_old_replicaset_are_ignored
    fixture_set = load_fixture_data("basic", ["configmap-data", "web"])
    deployment = fixture_set["web"]["Deployment"].first
    container = deployment["spec"]["template"]["spec"]["activeDeadlineSeconds"] = 1
    deploy_loaded_fixture_set(fixture_set, wait: false) # this will never succeed as pods are killed after 1s

    sleep 1 # make sure to hit DeadlineExceeded on at least one pod

    deploy_fixture_set("basic", subset: ["web", "configmap-data"])
    pods = kubeclient.get_pods(namespace: @namespace, label_selector: "name=web,app=basic")
    running_pods, not_running_pods = pods.partition { |pod| pod.status.phase == "Running" }
    assert_equal 1, running_pods.size
    assert not_running_pods.size >= 1
  end

  def test_bad_container_image_on_run_once_halts_and_fails_deploy
    fixture_set = load_fixture_data("basic")
    pod = fixture_set["unmanaged-pod"]["Pod"].first
    pod["spec"]["activeDeadlineSeconds"] = 3
    pod["spec"]["containers"].first["image"] = "hello-world:thisImageIsBad"

    assert_raises(KubernetesDeploy::FatalDeploymentError, /1 priority resources failed to deploy/) do
      deploy_loaded_fixture_set(fixture_set)
    end

    basic = FixtureSetAssertions::Basic.new(@namespace)
    basic.assert_unmanaged_pod_statuses("Failed")
    basic.assert_configmap_data_present # priority resource
    basic.refute_redis_resources_exist(expect_pvc: true) # pvc is priority resource
    basic.refute_web_resources_exist
  end

  def test_wait_false_still_waits_for_priority_resources
    fixture_set = load_fixture_data("basic")
    pod = fixture_set["unmanaged-pod"]["Pod"].first
    pod["spec"]["activeDeadlineSeconds"] = 1
    pod["spec"]["containers"].first["image"] = "hello-world:thisImageIsBad"

    assert_raises(KubernetesDeploy::FatalDeploymentError, /1 priority resources failed to deploy/) do
      deploy_loaded_fixture_set(fixture_set)
    end
    assert_logs_match(/DeadlineExceeded/)
  end

  def test_wait_false_ignores_non_priority_resource_failures
    # web depends on configmap so will not succeed deployed alone
    deploy_fixture_set("basic", subset: ["web"], wait: false)

    pods = kubeclient.get_pods(namespace: @namespace, label_selector: 'name=web,app=basic')
    assert_equal 1, pods.size, "Unable to find web pod"
    assert_equal "Pending", pods.first.status.phase
  end
end
