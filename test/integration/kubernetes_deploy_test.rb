# frozen_string_literal: true
require 'test_helper'

class KubernetesDeployTest < KubernetesDeploy::IntegrationTest
  def test_full_hello_cloud_set_deploy_succeeds
    assert deploy_fixtures("hello-cloud")
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_all_up
  end

  def test_partial_deploy_followed_by_full_deploy
    assert deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "redis.yml"])
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_all_redis_resources_up
    hello_cloud.assert_configmap_data_present
    hello_cloud.refute_managed_pod_exists
    hello_cloud.refute_web_resources_exist

    assert deploy_fixtures("hello-cloud")
    hello_cloud.assert_all_up
  end

  def test_pruning_works
    assert deploy_fixtures("hello-cloud")
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_all_up

    assert deploy_fixtures("hello-cloud", subset: ["redis.yml"])
    hello_cloud.assert_all_redis_resources_up
    hello_cloud.refute_configmap_data_exists
    hello_cloud.refute_managed_pod_exists
    hello_cloud.refute_web_resources_exist

    expected_pruned = [
      'configmap "hello-cloud-configmap-data"',
      'pod "unmanaged-pod-',
      'service "web"',
      'deployment "web"',
      'ingress "web"'
    ] # not necessarily listed in this order
    assert_logs_match(/Pruned 5 resources and successfully deployed 3 resources/)
    expected_pruned.each do |resource|
      assert_logs_match(/The following resources were pruned:.*#{resource}/)
    end
  end

  def test_pruning_disabled
    assert deploy_fixtures("hello-cloud", subset: ["configmap-data.yml"])
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_configmap_data_present

    assert deploy_fixtures("hello-cloud", subset: ["redis.yml"], prune: false)
    hello_cloud.assert_configmap_data_present
    hello_cloud.assert_all_redis_resources_up
  end

  def test_deploying_to_protected_namespace_with_override_does_not_prune
    KubernetesDeploy::Runner.stub_const(:PROTECTED_NAMESPACES, [@namespace]) do
      assert deploy_fixtures("hello-cloud", allow_protected_ns: true, prune: false)
      hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
      hello_cloud.assert_all_up
      assert_logs_match(/cannot be pruned/)
      assert_logs_match(/Please do not deploy to #{@namespace} unless you really know what you are doing/)

      assert deploy_fixtures("hello-cloud", subset: ["redis.yml"], allow_protected_ns: true, prune: false)
      hello_cloud.assert_all_up
    end
  end

  def test_refuses_deploy_to_protected_namespace_with_override_if_pruning_enabled
    KubernetesDeploy::Runner.stub_const(:PROTECTED_NAMESPACES, [@namespace]) do
      refute deploy_fixtures("hello-cloud", allow_protected_ns: true, prune: true)
    end
    assert_logs_match(/Refusing to deploy to protected namespace .* pruning enabled/)
  end

  def test_refuses_deploy_to_protected_namespace_without_override
    KubernetesDeploy::Runner.stub_const(:PROTECTED_NAMESPACES, [@namespace]) do
      refute deploy_fixtures("hello-cloud", prune: false)
    end
    assert_logs_match(/Refusing to deploy to protected namespace/)
  end

  def test_pvcs_are_not_pruned
    assert deploy_fixtures("hello-cloud", subset: ["redis.yml"])
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_all_redis_resources_up

    assert deploy_fixtures("hello-cloud", subset: ["configmap-data.yml"])
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

    success = deploy_fixtures("hello-cloud", subset: ["configmap-data.yml"]) do |fixtures|
      fixtures["secret.yml"] = { "Secret" => secret }
    end
    assert_equal true, success, "Deploy failed when it was expected to succeed"

    live_secret = kubeclient.get_secret("test", @namespace)
    assert_equal({ foo: "YmFy" }, live_secret["data"].to_h)
  end

  def test_invalid_yaml_fails_fast
    refute deploy_dir(fixture_path("invalid"))
    assert_logs_match(/Template 'yaml-error.yml' cannot be parsed/)
    assert_logs_match(/datapoint1: value1:/)
  end

  def test_invalid_k8s_spec_that_is_valid_yaml_fails_fast
    success = deploy_fixtures("hello-cloud", subset: ["configmap-data.yml"]) do |fixtures|
      configmap = fixtures["configmap-data.yml"]["ConfigMap"].first
      configmap["metadata"]["myKey"] = "uhOh"
    end
    assert_equal false, success, "Deploy succeeded when it was expected to fail"

    assert_logs_match(/'configmap-data.yml' is not a valid Kubernetes template/)
    assert_logs_match(/error validating data\: found invalid field myKey for v1.ObjectMeta/)
  end

  def test_dynamic_erb_collection_works
    assert deploy_raw_fixtures("collection-with-erb", bindings: { binding_test_a: 'foo', binding_test_b: 'bar' })

    deployments = v1beta1_kubeclient.get_deployments(namespace: @namespace)
    assert_equal 3, deployments.size
    assert_equal ["web-one", "web-three", "web-two"], deployments.map { |d| d.metadata.name }.sort
  end

  # Reproduces k8s bug
  # https://github.com/kubernetes/kubernetes/issues/42057
  def test_invalid_k8s_spec_that_is_valid_yaml_fails_on_apply
    success = deploy_fixtures("hello-cloud", subset: ["configmap-data.yml"]) do |fixtures|
      configmap = fixtures["configmap-data.yml"]["ConfigMap"].first
      configmap["metadata"]["labels"] = {
        "name" => { "not_a_name" => [1, 2] }
      }
    end
    assert_equal false, success, "Deploy succeeded when it was expected to fail"

    assert_logs_match(/Command failed: apply -f/)
    assert_logs_match(/Error from server \(BadRequest\): error when creating/)
    assert_logs_match(/Rendered template content:/)
    assert_logs_match(/not_a_name:/)
  end

  def test_dead_pods_in_old_replicaset_are_ignored
    success = deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb"], wait: false) do |fixtures|
      deployment = fixtures["web.yml.erb"]["Deployment"].first
      # web pods will get killed after one second and will not be cleaned up
      deployment["spec"]["template"]["spec"]["activeDeadlineSeconds"] = 1
    end
    assert_equal true, success, "Deploy failed when it was expected to succeed"

    initial_failed_pod_count = 0
    while initial_failed_pod_count < 1
      pods = kubeclient.get_pods(namespace: @namespace, label_selector: "name=web,app=hello-cloud")
      initial_failed_pod_count = pods.count { |pod| pod.status.phase == "Failed" }
    end

    assert deploy_fixtures("hello-cloud", subset: ["web.yml.erb", "configmap-data.yml"])
    pods = kubeclient.get_pods(namespace: @namespace, label_selector: "name=web,app=hello-cloud")
    running_pod_count = pods.count { |pod| pod.status.phase == "Running" }
    final_failed_pod_count = pods.count { |pod| pod.status.phase == "Failed" }

    assert_equal 1, running_pod_count
    assert final_failed_pod_count >= initial_failed_pod_count # failed pods not cleaned up
  end

  def test_bad_container_image_on_run_once_halts_and_fails_deploy
    success = deploy_fixtures("hello-cloud") do |fixtures|
      pod = fixtures["unmanaged-pod.yml.erb"]["Pod"].first
      pod["spec"]["activeDeadlineSeconds"] = 1
      pod["spec"]["containers"].first["image"] = "hello-world:thisImageIsBad"
    end
    assert_equal false, success, "Deploy succeeded when it was expected to fail"
    assert_logs_match("Failed to deploy 1 priority resource")
    assert_logs_match(%r{Pod\/unmanaged-pod-\w+-\w+: FAILED})

    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_unmanaged_pod_statuses("Failed")
    hello_cloud.assert_configmap_data_present # priority resource
    hello_cloud.refute_redis_resources_exist(expect_pvc: true) # pvc is priority resource
    hello_cloud.refute_web_resources_exist
  end

  def test_wait_false_still_waits_for_priority_resources
    success = deploy_fixtures("hello-cloud") do |fixtures|
      pod = fixtures["unmanaged-pod.yml.erb"]["Pod"].first
      pod["spec"]["activeDeadlineSeconds"] = 1
      pod["spec"]["containers"].first["image"] = "hello-world:thisImageIsBad"
    end
    assert_equal false, success, "Deploy succeeded when it was expected to fail"
    assert_logs_match("Failed to deploy 1 priority resource")
    assert_logs_match(%r{Pod\/unmanaged-pod-\w+-\w+: FAILED})
    assert_logs_match(/DeadlineExceeded/)
  end

  def test_wait_false_ignores_non_priority_resource_failures
    # web depends on configmap so will not succeed deployed alone
    assert deploy_fixtures("hello-cloud", subset: ["web.yml.erb"], wait: false)
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_deployment_up("web", replicas: 0) # it exists, but no pods available yet
    assert_logs_match("Result: SUCCESS")
    assert_logs_match("Deployed 3 resources")
    assert_logs_match("Deploy result verification is disabled for this deploy.")
  end

  def test_extra_bindings_should_be_rendered
    assert deploy_fixtures('collection-with-erb', subset: ["conf_map.yaml.erb"],
      bindings: { binding_test_a: 'binding_test_a', binding_test_b: 'binding_test_b' })

    map = kubeclient.get_config_map('extra-binding', @namespace).data
    assert_equal 'binding_test_a', map['BINDING_TEST_A']
    assert_equal 'binding_test_b', map['BINDING_TEST_B']
  end

  def test_deploy_fails_if_required_binding_not_present
    refute deploy_fixtures('collection-with-erb', subset: ["conf_map.yaml.erb"])
    assert_logs_match("Template 'conf_map.yaml.erb' cannot be rendered")
  end

  def test_long_running_deployment
    2.times do
      assert deploy_fixtures('long-running')
    end

    pods = kubeclient.get_pods(namespace: @namespace, label_selector: 'name=jobs,app=fixtures')
    assert_equal 4, pods.size

    count = count_by_revisions(pods)
    assert_equal [2, 2], count.values
  end

  def test_create_and_update_secrets_from_ejson
    ejson_cloud = FixtureSetAssertions::EjsonCloud.new(@namespace)
    ejson_cloud.create_ejson_keys_secret
    assert deploy_fixtures("ejson-cloud")
    ejson_cloud.assert_all_up
    assert_logs_match(/Creating secret catphotoscom/)
    assert_logs_match(/Creating secret unused-secret/)
    assert_logs_match(/Creating secret monitoring-token/)

    success = deploy_fixtures("ejson-cloud") do |fixtures|
      fixtures["secrets.ejson"]["kubernetes_secrets"]["unused-secret"]["data"] = { "_test" => "a" }
    end
    assert_equal true, success, "Deploy failed when it was expected to succeed"
    ejson_cloud.assert_secret_present('unused-secret', { "test" => "a" }, managed: true)
    ejson_cloud.assert_web_resources_up
    assert_logs_match(/Updating secret unused-secret/)
  end

  def test_create_ejson_secrets_with_malformed_secret_data
    ejson_cloud = FixtureSetAssertions::EjsonCloud.new(@namespace)
    ejson_cloud.create_ejson_keys_secret

    malformed = { "_bad_data" => %w(foo bar) }
    success = deploy_fixtures("ejson-cloud") do |fixtures|
      fixtures["secrets.ejson"]["kubernetes_secrets"]["monitoring-token"]["data"] = malformed
    end
    assert_equal false, success, "Deploy succeeded when it was expected to fail"
    assert_logs_match(/data for secret monitoring-token was invalid/)
  end

  def test_pruning_of_secrets_created_from_ejson
    ejson_cloud = FixtureSetAssertions::EjsonCloud.new(@namespace)
    ejson_cloud.create_ejson_keys_secret
    assert deploy_fixtures("ejson-cloud")
    ejson_cloud.assert_secret_present('unused-secret', managed: true)

    success = deploy_fixtures("ejson-cloud") do |fixtures|
      fixtures["secrets.ejson"]["kubernetes_secrets"].delete("unused-secret")
    end
    assert_equal true, success, "Deploy failed when it was expected to succeed"
    assert_logs_match(/Pruning secret unused-secret/)

    # The removed secret was pruned
    ejson_cloud.refute_resource_exists('secret', 'unused-secret')
    # The remaining secrets exist
    ejson_cloud.assert_secret_present('monitoring-token', managed: true)
    ejson_cloud.assert_secret_present('catphotoscom', type: 'kubernetes.io/tls', managed: true)
    # The unmanaged secret was not pruned
    ejson_cloud.assert_secret_present('ejson-keys', managed: false)
  end

  def test_pruning_of_existing_managed_secrets_when_ejson_file_has_been_deleted
    ejson_cloud = FixtureSetAssertions::EjsonCloud.new(@namespace)
    ejson_cloud.create_ejson_keys_secret
    assert deploy_fixtures("ejson-cloud")
    ejson_cloud.assert_all_up

    success = deploy_fixtures("ejson-cloud") do |fixtures|
      fixtures.delete("secrets.ejson")
    end
    assert_equal true, success, "Deploy failed when it was expected to succeed"

    assert_logs_match("Pruning secret unused-secret")
    assert_logs_match("Pruning secret catphotoscom")
    assert_logs_match("Pruning secret monitoring-token")

    ejson_cloud.refute_resource_exists('secret', 'unused-secret')
    ejson_cloud.refute_resource_exists('secret', 'catphotoscom')
    ejson_cloud.refute_resource_exists('secret', 'monitoring-token')
  end

  def test_deploy_result_logging_for_mixed_result_deploy
    KubernetesDeploy::Pod.any_instance.stubs(:deploy_failed?).returns(false, false, false, false, true)
    service_timeout = 5
    KubernetesDeploy::Service.any_instance.stubs(:timeout).returns(service_timeout)

    success = deploy_fixtures("hello-cloud", subset: ["web.yml.erb", "configmap-data.yml"]) do |fixtures|
      web = fixtures["web.yml.erb"]["Deployment"].first
      app = web["spec"]["template"]["spec"]["containers"].first
      app["command"] = ["/usr/sbin/nginx", "-s", "stop"] # it isn't running, so this will log some errors
      sidecar = web["spec"]["template"]["spec"]["containers"].last
      sidecar["command"] = ["ls", "/not-a-dir"]
    end
    assert_equal false, success, "Deploy succeeded when it was expected to fail"

    # List of successful resources
    assert_logs_match(%r{ConfigMap/hello-cloud-configmap-data\s+Available})
    assert_logs_match(%r{Ingress/web\s+Created})

    # Debug info for service timeout
    assert_logs_match("Service/web: TIMED OUT (limit: #{service_timeout}s)")
    assert_logs_match("service does not have any endpoints")
    assert_logs_match("Final status: 0 endpoints")

    # Debug info for deployment failure
    assert_logs_match("Deployment/web: FAILED")
    assert_logs_match("Final status: 1 updatedReplicas, 1 replicas, 1 unavailableReplicas")
    assert_logs_match(%r{\[Deployment/web\].*Scaled up replica set web-}) # deployment event
    assert_logs_match(/Back-off restarting failed container/) # event
    assert_logs_match("nginx: [error]") # app log
    assert_logs_match("ls: /not-a-dir: No such file or directory") # sidecar log

    refute_logs_match(/Started container with id/)
    refute_logs_match(/Created container with id/)
  end

  def test_failed_deploy_to_nonexistent_namespace
    original_ns = @namespace
    @namespace = 'this-certainly-should-not-exist'
    refute deploy_fixtures("hello-cloud", subset: ['configmap-data.yml'])
    assert_logs_match(/Result: FAILURE.*Namespace this-certainly-should-not-exist not found/m)
  ensure
    @namespace = original_ns
  end

  def test_failure_logs_from_unmanaged_pod_appear_in_summary_section
    success = deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "unmanaged-pod.yml.erb"]) do |fixtures|
      pod = fixtures["unmanaged-pod.yml.erb"]["Pod"].first
      container = pod["spec"]["containers"].first
      container["command"] = ["/some/bad/path"] # should throw an error
    end
    assert_equal false, success

    assert_logs_match("Failed to deploy 1 priority resource")
    assert_logs_match("Container command '/some/bad/path' not found or does not exist") # from an event
    assert_logs_match(/Result.*no such file or directory/m) # from logs
    refute_logs_match(/no such file or directory.*Result/m) # logs not also displayed before summary
  end

  def test_unusual_timeout_output
    KubernetesDeploy::ConfigMap.any_instance.stubs(:deploy_succeeded?).returns(false)
    KubernetesDeploy::ConfigMap.any_instance.stubs(:timeout).returns(2)
    refute deploy_fixtures('hello-cloud', subset: ["configmap-data.yml"])
    assert_logs_match("It is very unusual for this resource type to fail to deploy. Please try the deploy again.")
    assert_logs_match("Final status: Available")
  end

  # ref https://github.com/kubernetes/kubernetes/issues/26202
  def test_output_when_switching_labels_incorrectly
    assert deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb"])
    success = deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb"]) do |fixtures|
      web = fixtures["web.yml.erb"]["Deployment"].first
      web["spec"]["template"]["metadata"]["labels"] = { "name" => "foobar" }
    end
    assert_equal false, success
    assert_logs_match("one of your templates is invalid")
    assert_logs_match(/The Deployment "web" is invalid.*`selector` does not match template `labels`/)
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
