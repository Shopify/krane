require 'test_helper'

class KubernetesDeployTest < KubernetesDeploy::IntegrationTest
  def test_full_basic_set_deploy_succeeds
    deploy_fixtures("basic")
    basic = FixtureSetAssertions::Basic.new(@namespace)
    basic.assert_all_up
  end

  def test_partial_deploy_followed_by_full_deploy
    deploy_fixtures("basic", subset: ["configmap-data.yml", "redis.yml"])
    basic = FixtureSetAssertions::Basic.new(@namespace)
    basic.assert_all_redis_resources_up
    basic.assert_configmap_data_present
    basic.refute_managed_pod_exists
    basic.refute_web_resources_exist

    deploy_fixtures("basic")
    basic.assert_all_up
  end

  def test_pruning
    deploy_fixtures("basic")
    basic = FixtureSetAssertions::Basic.new(@namespace)
    basic.assert_all_up

    deploy_fixtures("basic", subset: ["redis.yml"])
    basic.assert_all_redis_resources_up
    basic.refute_configmap_data_exists
    basic.refute_managed_pod_exists
    basic.refute_web_resources_exist
  end

  def test_pvcs_are_not_pruned
    deploy_fixtures("basic", subset: ["redis.yml"])
    basic = FixtureSetAssertions::Basic.new(@namespace)
    basic.assert_all_redis_resources_up

    deploy_fixtures("basic", subset: ["configmap-data.yml"])
    basic.assert_configmap_data_present
    basic.refute_redis_resources_exist(expect_pvc: true)
  end

  def test_success_with_unrecognized_resource_type
    # Secrets are intentionally unsupported because they should not be committed to your repo
    secret = {
      "apiVersion" => "v1",
      "kind" => "Secret",
      "metadata" => { "name" => "test" },
      "data" => { "foo" => "YmFy" }
    }

    deploy_fixtures("basic", subset: ["configmap-data.yml"]) do |fixtures|
      fixtures["secret.yml"] = { "Secret" => secret }
    end

    live_secret = kubeclient.get_secret("test", @namespace)
    assert_equal({ foo: "YmFy" }, live_secret["data"].to_h)
  end

  def test_invalid_yaml_fails_fast
    assert_raises(KubernetesDeploy::FatalDeploymentError, /Template \S+yaml-error\S+ cannot be parsed/) do
      deploy_dir(fixture_path("invalid"))
    end
  end

  def test_invalid_k8s_spec_that_is_valid_yaml_fails_fast
    assert_raises(KubernetesDeploy::FatalDeploymentError, /Dry run failed for template configmap-data/) do
      deploy_fixtures("basic", subset: ["configmap-data.yml"]) do |fixtures|
        configmap = fixtures["configmap-data.yml"]["ConfigMap"].first
        configmap["metadata"]["myKey"] = "uhOh"
      end
    end
    assert_logs_match(/error validating data\: found invalid field myKey for v1.ObjectMeta/)
  end

  # Reproduces k8s bug
  # https://github.com/kubernetes/kubernetes/issues/42057
  def test_invalid_k8s_spec_that_is_valid_yaml_fails_on_apply
    err = assert_raises(KubernetesDeploy::FatalDeploymentError) do
      deploy_fixtures("basic", subset: ["configmap-data.yml"]) do |fixtures|
        configmap = fixtures["configmap-data.yml"]["ConfigMap"].first
        configmap["metadata"]["labels"] = {
          "name" => { "not_a_name" => [1, 2] }
        }
      end
    end
    assert_match(/The following command failed/, err.to_s)
    assert_match(/error: unable to decode/, err.to_s)
    assert_logs_match(/Inspecting the file mentioned in the error message/)
  end

  def test_dead_pods_in_old_replicaset_are_ignored
    deploy_fixtures("basic", subset: ["configmap-data.yml", "web.yml.erb"], wait: false) do |fixtures|
      deployment = fixtures["web.yml.erb"]["Deployment"].first
      # web pods will get killed after one second and will not be cleaned up
      container = deployment["spec"]["template"]["spec"]["activeDeadlineSeconds"] = 1
    end

    sleep 1 # make sure to hit DeadlineExceeded on at least one pod

    deploy_fixtures("basic", subset: ["web.yml.erb", "configmap-data.yml"])
    pods = kubeclient.get_pods(namespace: @namespace, label_selector: "name=web,app=basic")
    running_pods, not_running_pods = pods.partition { |pod| pod.status.phase == "Running" }
    assert_equal 1, running_pods.size
    assert not_running_pods.size >= 1
  end

  def test_bad_container_image_on_run_once_halts_and_fails_deploy
    assert_raises(KubernetesDeploy::FatalDeploymentError, /1 priority resources failed to deploy/) do
      deploy_fixtures("basic") do |fixtures|
        pod = fixtures["unmanaged-pod.yml.erb"]["Pod"].first
        pod["spec"]["activeDeadlineSeconds"] = 1
        pod["spec"]["containers"].first["image"] = "hello-world:thisImageIsBad"
      end
    end

    basic = FixtureSetAssertions::Basic.new(@namespace)
    basic.assert_unmanaged_pod_statuses("Failed")
    basic.assert_configmap_data_present # priority resource
    basic.refute_redis_resources_exist(expect_pvc: true) # pvc is priority resource
    basic.refute_web_resources_exist
  end

  def test_wait_false_still_waits_for_priority_resources
    assert_raises(KubernetesDeploy::FatalDeploymentError, /1 priority resources failed to deploy/) do
      deploy_fixtures("basic") do |fixtures|
        pod = fixtures["unmanaged-pod.yml.erb"]["Pod"].first
        pod["spec"]["activeDeadlineSeconds"] = 1
        pod["spec"]["containers"].first["image"] = "hello-world:thisImageIsBad"
      end
    end
    assert_logs_match(/DeadlineExceeded/)
  end

  def test_wait_false_ignores_non_priority_resource_failures
    # web depends on configmap so will not succeed deployed alone
    deploy_fixtures("basic", subset: ["web.yml.erb"], wait: false)

    pods = kubeclient.get_pods(namespace: @namespace, label_selector: 'name=web,app=basic')
    assert_equal 1, pods.size, "Unable to find web pod"
    assert_equal "Pending", pods.first.status.phase
  end
end
