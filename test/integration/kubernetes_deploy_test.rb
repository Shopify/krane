# frozen_string_literal: true
require 'test_helper'

class KubernetesDeployTest < KubernetesDeploy::IntegrationTest
  def test_full_hello_cloud_set_deploy_succeeds
    deploy_fixtures("hello-cloud")
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_all_up
  end

  def test_partial_deploy_followed_by_full_deploy
    deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "redis.yml"])
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_all_redis_resources_up
    hello_cloud.assert_configmap_data_present
    hello_cloud.refute_managed_pod_exists
    hello_cloud.refute_web_resources_exist

    deploy_fixtures("hello-cloud")
    hello_cloud.assert_all_up
  end

  def test_pruning
    deploy_fixtures("hello-cloud")
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_all_up

    deploy_fixtures("hello-cloud", subset: ["redis.yml"])
    hello_cloud.assert_all_redis_resources_up
    hello_cloud.refute_configmap_data_exists
    hello_cloud.refute_managed_pod_exists
    hello_cloud.refute_web_resources_exist
  end

  def test_pruning_disabled
    deploy_fixtures("hello-cloud", subset: ["configmap-data.yml"])
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_configmap_data_present

    deploy_fixtures("hello-cloud", subset: ["redis.yml"], prune: false)
    hello_cloud.assert_configmap_data_present
    hello_cloud.assert_all_redis_resources_up
  end

  def test_deploying_to_protected_namespace_with_override_does_not_prune
    KubernetesDeploy::Runner.stub_const(:PROTECTED_NAMESPACES, [@namespace]) do
      deploy_fixtures("hello-cloud", allow_protected_ns: true, prune: false)
      hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
      hello_cloud.assert_all_up
      assert_logs_match(/cannot be pruned/)
      assert_logs_match(/Please do not deploy to #{@namespace} unless you really know what you are doing/)

      deploy_fixtures("hello-cloud", subset: ["redis.yml"], allow_protected_ns: true, prune: false)
      hello_cloud.assert_all_up
    end
  end

  def test_refuses_deploy_to_protected_namespace_with_override_if_pruning_enabled
    expected_msg = /Refusing to deploy to protected namespace .* pruning enabled/
    assert_raises_message(KubernetesDeploy::FatalDeploymentError, expected_msg) do
      KubernetesDeploy::Runner.stub_const(:PROTECTED_NAMESPACES, [@namespace]) do
        deploy_fixtures("hello-cloud", allow_protected_ns: true, prune: true)
      end
    end
  end

  def test_refuses_deploy_to_protected_namespace_without_override
    assert_raises_message(KubernetesDeploy::FatalDeploymentError, /Refusing to deploy to protected namespace/) do
      KubernetesDeploy::Runner.stub_const(:PROTECTED_NAMESPACES, [@namespace]) do
        deploy_fixtures("hello-cloud", prune: false)
      end
    end
  end

  def test_pvcs_are_not_pruned
    deploy_fixtures("hello-cloud", subset: ["redis.yml"])
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_all_redis_resources_up

    deploy_fixtures("hello-cloud", subset: ["configmap-data.yml"])
    hello_cloud.assert_configmap_data_present
    hello_cloud.refute_redis_resources_exist(expect_pvc: true)
  end

  def test_success_with_unrecognized_resource_type
    # Secrets are intentionally unsupported because they should not be committed to your repo
    secret = {
      "apiVersion" => "v1",
      "kind" => "Secret",
      "metadata" => { "name" => "test" },
      "data" => { "foo" => "YmFy" }
    }

    deploy_fixtures("hello-cloud", subset: ["configmap-data.yml"]) do |fixtures|
      fixtures["secret.yml"] = { "Secret" => secret }
    end

    live_secret = kubeclient.get_secret("test", @namespace)
    assert_equal({ foo: "YmFy" }, live_secret["data"].to_h)
  end

  def test_invalid_yaml_fails_fast
    assert_raises_message(KubernetesDeploy::FatalDeploymentError, /Template yaml-error.yml cannot be parsed/) do
      deploy_dir(fixture_path("invalid"))
    end
  end

  def test_invalid_k8s_spec_that_is_valid_yaml_fails_fast
    assert_raises_message(KubernetesDeploy::FatalDeploymentError, /Dry run failed for template configmap-data/) do
      deploy_fixtures("hello-cloud", subset: ["configmap-data.yml"]) do |fixtures|
        configmap = fixtures["configmap-data.yml"]["ConfigMap"].first
        configmap["metadata"]["myKey"] = "uhOh"
      end
    end
    assert_logs_match(/error validating data\: found invalid field myKey for v1.ObjectMeta/)
  end

  def test_dynamic_erb_collection_works
    deploy_raw_fixtures("collection-with-erb", bindings: { binding_test_a: 'foo', binding_test_b: 'bar' })

    deployments = v1beta1_kubeclient.get_deployments(namespace: @namespace)
    assert_equal 3, deployments.size
    assert_equal ["web-one", "web-three", "web-two"], deployments.map { |d| d.metadata.name }.sort
  end

  # Reproduces k8s bug
  # https://github.com/kubernetes/kubernetes/issues/42057
  def test_invalid_k8s_spec_that_is_valid_yaml_fails_on_apply
    err = assert_raises(KubernetesDeploy::FatalDeploymentError) do
      deploy_fixtures("hello-cloud", subset: ["configmap-data.yml"]) do |fixtures|
        configmap = fixtures["configmap-data.yml"]["ConfigMap"].first
        configmap["metadata"]["labels"] = {
          "name" => { "not_a_name" => [1, 2] }
        }
      end
    end
    assert_match(/The following command failed: apply/, err.to_s)
    assert_match(/Error from server \(BadRequest\): error when creating/, err.to_s)
    assert_logs_match(/Inspecting the file mentioned in the error message/)
  end

  def test_dead_pods_in_old_replicaset_are_ignored
    deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb"], wait: false) do |fixtures|
      deployment = fixtures["web.yml.erb"]["Deployment"].first
      # web pods will get killed after one second and will not be cleaned up
      deployment["spec"]["template"]["spec"]["activeDeadlineSeconds"] = 1
    end

    initial_failed_pod_count = 0
    while initial_failed_pod_count < 1
      pods = kubeclient.get_pods(namespace: @namespace, label_selector: "name=web,app=hello-cloud")
      initial_failed_pod_count = pods.count { |pod| pod.status.phase == "Failed" }
    end

    deploy_fixtures("hello-cloud", subset: ["web.yml.erb", "configmap-data.yml"])
    pods = kubeclient.get_pods(namespace: @namespace, label_selector: "name=web,app=hello-cloud")
    running_pod_count = pods.count { |pod| pod.status.phase == "Running" }
    final_failed_pod_count = pods.count { |pod| pod.status.phase == "Failed" }

    assert_equal 1, running_pod_count
    assert final_failed_pod_count >= initial_failed_pod_count # failed pods not cleaned up
  end

  def test_bad_container_image_on_run_once_halts_and_fails_deploy
    expected_msg = %r{The following priority resources failed to deploy: Pod\/unmanaged-pod}
    assert_raises_message(KubernetesDeploy::FatalDeploymentError, expected_msg) do
      deploy_fixtures("hello-cloud") do |fixtures|
        pod = fixtures["unmanaged-pod.yml.erb"]["Pod"].first
        pod["spec"]["activeDeadlineSeconds"] = 1
        pod["spec"]["containers"].first["image"] = "hello-world:thisImageIsBad"
      end
    end

    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_unmanaged_pod_statuses("Failed")
    hello_cloud.assert_configmap_data_present # priority resource
    hello_cloud.refute_redis_resources_exist(expect_pvc: true) # pvc is priority resource
    hello_cloud.refute_web_resources_exist
  end

  def test_wait_false_still_waits_for_priority_resources
    expected_msg = %r{The following priority resources failed to deploy: Pod\/unmanaged-pod}
    assert_raises_message(KubernetesDeploy::FatalDeploymentError, expected_msg) do
      deploy_fixtures("hello-cloud") do |fixtures|
        pod = fixtures["unmanaged-pod.yml.erb"]["Pod"].first
        pod["spec"]["activeDeadlineSeconds"] = 1
        pod["spec"]["containers"].first["image"] = "hello-world:thisImageIsBad"
      end
    end
    assert_logs_match(/DeadlineExceeded/)
  end

  def test_wait_false_ignores_non_priority_resource_failures
    # web depends on configmap so will not succeed deployed alone
    deploy_fixtures("hello-cloud", subset: ["web.yml.erb"], wait: false)

    pods = kubeclient.get_pods(namespace: @namespace, label_selector: 'name=web,app=hello-cloud')
    assert_equal 1, pods.size, "Unable to find web pod"
    assert_equal "Pending", pods.first.status.phase
  end

  def test_extra_bindings_should_be_rendered
    deploy_fixtures('collection-with-erb', subset: ["conf_map.yml.erb"],
      bindings: { binding_test_a: 'binding_test_a', binding_test_b: 'binding_test_b' })

    map = kubeclient.get_config_map('extra-binding', @namespace).data
    assert_equal 'binding_test_a', map['BINDING_TEST_A']
    assert_equal 'binding_test_b', map['BINDING_TEST_B']
  end

  def test_should_raise_if_required_binding_not_present
    assert_raises NameError do
      deploy_fixtures('collection-with-erb', subset: ["conf_map.yml.erb"])
    end
  end

  def test_long_running_deployment
    2.times do
      deploy_fixtures('long-running')
    end

    pods = kubeclient.get_pods(namespace: @namespace, label_selector: 'name=jobs,app=fixtures')
    assert_equal 4, pods.size

    count = count_by_revisions(pods)
    assert_equal [2, 2], count.values
  end

  private

  def count_by_revisions(pods)
    revisions = {}
    pods.each do |pod|
      rev = pod.spec.containers.first.env.find { |var| var.name == "GITHUB_REV" }.value
      revisions[rev] ||= 0
      revisions[rev] += 1
    end
    revisions
  end
end
