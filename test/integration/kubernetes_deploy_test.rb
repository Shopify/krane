# frozen_string_literal: true
require 'test_helper'

class KubernetesDeployTest < KubernetesDeploy::IntegrationTest
  def test_full_hello_cloud_set_deploy_succeeds
    assert_deploy_success(deploy_fixtures("hello-cloud"))
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_all_up

    assert_logs_match_all([
      "Deploying ConfigMap/hello-cloud-configmap-data (timeout: 30s)",
      "Hello from Docker!", # unmanaged pod logs
      "Result: SUCCESS",
      "Successfully deployed 14 resources"
    ], in_order: true)

    assert_logs_match_all([
      %r{ReplicaSet/bare-replica-set\s+1 replica, 1 availableReplica, 1 readyReplica},
      %r{Deployment/web\s+1 replica, 1 updatedReplica, 1 availableReplica},
      %r{Service/web\s+Selects at least 1 pod},
      %r{DaemonSet/nginx\s+1 currentNumberScheduled, 1 desiredNumberScheduled, 1 numberReady}
    ])

    # Verify that success section isn't duplicated for predeployed resources
    assert_logs_match("Successful resources", 1)
    assert_logs_match(%r{ConfigMap/hello-cloud-configmap-data\s+Available}, 1)
  end

  def test_partial_deploy_followed_by_full_deploy
    assert_deploy_success(deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "redis.yml"]))
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_all_redis_resources_up
    hello_cloud.assert_configmap_data_present
    hello_cloud.refute_managed_pod_exists
    hello_cloud.refute_web_resources_exist

    assert_deploy_success(deploy_fixtures("hello-cloud"))
    hello_cloud.assert_all_up
  end

  def test_pruning_works
    assert_deploy_success(deploy_fixtures("hello-cloud"))
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_all_up

    assert_deploy_success(deploy_fixtures("hello-cloud", subset: ["redis.yml"]))
    hello_cloud.assert_all_redis_resources_up
    hello_cloud.refute_configmap_data_exists
    hello_cloud.refute_managed_pod_exists
    hello_cloud.refute_web_resources_exist

    expected_pruned = [
      'configmap "hello-cloud-configmap-data"',
      'pod "unmanaged-pod-',
      'service "web"',
      'deployment "web"',
      'ingress "web"',
      'daemonset "nginx"'
    ] # not necessarily listed in this order
    expected_msgs = [/Pruned 6 resources and successfully deployed 3 resources/]
    expected_pruned.map do |resource|
      expected_msgs << /The following resources were pruned:.*#{resource}/
    end
    assert_logs_match_all(expected_msgs)
  end

  def test_pruning_disabled
    assert_deploy_success(deploy_fixtures("hello-cloud", subset: ["configmap-data.yml"]))
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_configmap_data_present

    assert_deploy_success(deploy_fixtures("hello-cloud", subset: ["redis.yml"], prune: false))
    hello_cloud.assert_configmap_data_present
    hello_cloud.assert_all_redis_resources_up
  end

  def test_deploying_to_protected_namespace_with_override_does_not_prune
    KubernetesDeploy::Runner.stub_const(:PROTECTED_NAMESPACES, [@namespace]) do
      assert_deploy_success(deploy_fixtures("hello-cloud", allow_protected_ns: true, prune: false))
      hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
      hello_cloud.assert_all_up
      assert_logs_match_all([
        /cannot be pruned/,
        /Please do not deploy to #{@namespace} unless you really know what you are doing/
      ])

      result = deploy_fixtures("hello-cloud", subset: ["redis.yml"], allow_protected_ns: true, prune: false)
      assert_deploy_success(result)
      hello_cloud.assert_all_up
    end
  end

  def test_refuses_deploy_to_protected_namespace_with_override_if_pruning_enabled
    KubernetesDeploy::Runner.stub_const(:PROTECTED_NAMESPACES, [@namespace]) do
      assert_deploy_failure(deploy_fixtures("hello-cloud", allow_protected_ns: true, prune: true))
    end
    assert_logs_match(/Refusing to deploy to protected namespace .* pruning enabled/)
  end

  def test_refuses_deploy_to_protected_namespace_without_override
    KubernetesDeploy::Runner.stub_const(:PROTECTED_NAMESPACES, [@namespace]) do
      assert_deploy_failure(deploy_fixtures("hello-cloud", prune: false))
    end
    assert_logs_match(/Refusing to deploy to protected namespace/)
  end

  def test_pvcs_are_not_pruned
    assert_deploy_success(deploy_fixtures("hello-cloud", subset: ["redis.yml"]))
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_all_redis_resources_up

    assert_deploy_success(deploy_fixtures("hello-cloud", subset: ["configmap-data.yml"]))
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

    result = deploy_fixtures("hello-cloud", subset: ["configmap-data.yml"]) do |fixtures|
      fixtures["secret.yml"] = { "Secret" => secret }
    end
    assert_deploy_success(result)

    live_secret = kubeclient.get_secret("test", @namespace)
    assert_equal({ foo: "YmFy" }, live_secret["data"].to_h)
  end

  def test_invalid_yaml_fails_fast
    refute deploy_dir(fixture_path("invalid"))
    assert_logs_match_all([
      /Template 'yaml-error.yml' cannot be parsed/,
      /datapoint1: value1:/
    ])
  end

  def test_invalid_k8s_spec_that_is_valid_yaml_fails_fast_and_prints_template
    result = deploy_fixtures("hello-cloud", subset: ["configmap-data.yml"]) do |fixtures|
      configmap = fixtures["configmap-data.yml"]["ConfigMap"].first
      configmap["metadata"]["myKey"] = "uhOh"
    end
    assert_deploy_failure(result)

    assert_logs_match_all([
      "Template validation failed",
      /Invalid template: ConfigMap-hello-cloud-configmap-data.*yml/,
      "> Error from kubectl:",
      "error validating data: found invalid field myKey for v1.ObjectMeta",
      "> Rendered template content:",
      "      myKey: uhOh"
    ], in_order: true)
  end

  def test_dynamic_erb_collection_works
    assert deploy_raw_fixtures("collection-with-erb", bindings: { binding_test_a: 'foo', binding_test_b: 'bar' })

    deployments = v1beta1_kubeclient.get_deployments(namespace: @namespace)
    assert_equal 3, deployments.size
    assert_equal ["web-one", "web-three", "web-two"], deployments.map { |d| d.metadata.name }.sort
  end

  # The next three tests reproduce a k8s bug
  # The dry run should catch these problems, but it does not. Instead, apply fails.
  # https://github.com/kubernetes/kubernetes/issues/42057
  def test_invalid_k8s_spec_that_is_valid_yaml_fails_on_apply_and_prints_template
    result = deploy_fixtures("hello-cloud", subset: ["configmap-data.yml"]) do |fixtures|
      configmap = fixtures["configmap-data.yml"]["ConfigMap"].first
      configmap["metadata"]["labels"] = {
        "name" => { "not_a_name" => [1, 2] }
      }
    end
    assert_deploy_failure(result)
    assert_logs_match_all([
      "Command failed: apply -f",
      "WARNING: Any resources not mentioned in the error below were likely created/updated.",
      /Invalid template: ConfigMap-hello-cloud-configmap-data.*\.yml/,
      "> Error from kubectl:",
      "    Error from server (BadRequest): error when creating",
      "> Rendered template content:",
      "          not_a_name:",
    ], in_order: true)
  end

  def test_multiple_invalid_k8s_specs_fails_on_apply_and_prints_template
    result = deploy_fixtures("hello-cloud", subset: ["web.yml.erb"]) do |fixtures|
      bad_port_name = "http_test_is_really_long_and_invalid_chars"
      svc = fixtures["web.yml.erb"]["Service"].first
      svc["spec"]["ports"].first["targetPort"] = bad_port_name
      deployment = fixtures["web.yml.erb"]["Deployment"].first
      deployment["spec"]["template"]["spec"]["containers"].first["ports"].first["name"] = bad_port_name
    end

    assert_deploy_failure(result)
    assert_logs_match_all([
      "Command failed: apply -f",
      "WARNING: Any resources not mentioned in the error below were likely created/updated.",
      /Invalid templates: Service-web.*\.yml, Deployment-web.*\.yml/,
      "Error from server (Invalid): error when creating",
      "Error from server (Invalid): error when creating", # once for deployment, once for svc
      "> Rendered template content:",
      "        targetPort: http_test_is_really_long_and_invalid_chars", # error in svc template
      "              name: http_test_is_really_long_and_invalid_chars" # error in deployment template
    ], in_order: true)
  end

  def test_invalid_k8s_spec_that_is_valid_yaml_but_has_no_template_path_in_error_prints_helpful_message
    result = deploy_fixtures("hello-cloud", subset: ["web.yml.erb"]) do |fixtures|
      svc = fixtures["web.yml.erb"]["Service"].first
      svc["spec"]["ports"].first["targetPort"] = "http_test_is_really_long_and_invalid_chars"
    end
    assert_deploy_failure(result)
    assert_logs_match_all([
      "Command failed: apply -f",
      "WARNING: Any resources not mentioned in the error below were likely created/updated.",
      "Invalid templates: See error message",
      "> Error from kubectl:",
      '    The Service "web" is invalid:',
      'spec.ports[0].targetPort: Invalid value: "http_test_is_really_long_and_invalid_chars"'
    ], in_order: true)
  end

  def test_bad_container_image_on_run_once_halts_and_fails_deploy
    result = deploy_fixtures("hello-cloud") do |fixtures|
      pod = fixtures["unmanaged-pod.yml.erb"]["Pod"].first
      pod["spec"]["activeDeadlineSeconds"] = 1
      pod["spec"]["containers"].first["image"] = "hello-world:thisImageIsBad"
    end
    assert_deploy_failure(result)
    assert_logs_match("Failed to deploy 1 priority resource")
    assert_logs_match(%r{Pod\/unmanaged-pod-\w+-\w+: FAILED})

    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_unmanaged_pod_statuses("Failed")
    hello_cloud.assert_configmap_data_present # priority resource
    hello_cloud.refute_redis_resources_exist(expect_pvc: true) # pvc is priority resource
    hello_cloud.refute_web_resources_exist
  end

  def test_deployment_container_mounting_secret_that_does_not_exist_as_env_var_fails_quickly
    result = deploy_fixtures("ejson-cloud", subset: ["web.yaml"]) do |fixtures| # exclude secret ejson
      # Remove the volumes. Right now Kubernetes does not expose a useful status when mounting fails. :(
      deploy = fixtures["web.yaml"]["Deployment"].first
      deploy["spec"]["replicas"] = 3
      pod_spec = deploy["spec"]["template"]["spec"]
      pod_spec["volumes"] = []
      pod_spec["containers"].first["volumeMounts"] = []
    end
    assert_deploy_failure(result)

    assert_logs_match_all([
      "Deployment/web: FAILED",
      "The following containers are in a state that is unlikely to be recoverable:",
      "app: Failed to generate container configuration: secrets \"monitoring-token\" not found",
      "Final status: 3 replicas, 3 updatedReplicas, 3 unavailableReplicas"
    ], in_order: true)

    assert_logs_match("The following containers are in a state that is unlikely to be recoverable", 1) # no duplicates
  end

  def test_bad_container_image_on_deployment_pod_fails_quickly
    result = deploy_fixtures("invalid", subset: ["cannot_run.yml"]) do |fixtures|
      container = fixtures["cannot_run.yml"]["Deployment"].first["spec"]["template"]["spec"]["containers"].first
      container["image"] = "some-invalid-image:badtag"
    end
    assert_deploy_failure(result)

    assert_logs_match_all([
      "Deployment/cannot-run: FAILED",
      "The following containers are in a state that is unlikely to be recoverable:",
      "container-cannot-run: Failed to pull image some-invalid-image:badtag.",
      "Did you wait for it to be built and pushed to the registry before deploying?"
    ], in_order: true)
  end

  def test_bad_init_container_on_deployment_fails_quickly
    assert_deploy_failure(deploy_fixtures("invalid", subset: ["init_crash.yml"]))
    assert_logs_match_all([
      "Deployment/init-crash: FAILED",
      "The following containers are in a state that is unlikely to be recoverable:",
      "init-crash-loop-back-off: Crashing repeatedly (exit 1). See logs for more information.",
      "ls: /not-a-dir: No such file or directory" # logs
    ], in_order: true)
  end

  def test_crashing_container_on_deployment_fails_quickly
    assert_deploy_failure(deploy_fixtures("invalid", subset: ["crash_loop.yml"]))

    assert_logs_match_all([
      "Deployment/crash-loop: FAILED",
      "The following containers are in a state that is unlikely to be recoverable:",
      "crash-loop-back-off: Crashing repeatedly (exit 1). See logs for more information.",
      'nginx: [error] open() "/var/run/nginx.pid" failed (2: No such file or directory)' # Logs
    ], in_order: true)
  end

  def test_unrunnable_container_on_deployment_pod_fails_quickly
    assert_deploy_failure(deploy_fixtures("invalid", subset: ["cannot_run.yml"]))

    assert_logs_match_all([
      "Deployment/cannot-run: FAILED",
      "The following containers are in a state that is unlikely to be recoverable:",
      "container-cannot-run: Failed to start (exit 127):",
      "Container command '/some/bad/path' not found or does not exist."
    ], in_order: true)
  end

  def test_wait_false_still_waits_for_priority_resources
    result = deploy_fixtures("hello-cloud") do |fixtures|
      pod = fixtures["unmanaged-pod.yml.erb"]["Pod"].first
      pod["spec"]["containers"].first["image"] = "hello-world:thisImageIsBad"
    end
    assert_deploy_failure(result)
    assert_logs_match_all([
      "Failed to deploy 1 priority resource",
      %r{Pod\/unmanaged-pod-\w+-\w+: FAILED},
      "The following containers encountered errors:",
      "hello-cloud: Failed to pull image hello-world:thisImageIsBad"
    ])
  end

  def test_deployment_with_progress_times_out_for_short_duration
    # The deployment adds a progressDealineSeconds of 2s and attepts to deploy a container
    # which sleeps and cannot fulfill the readiness probe causing it to timeout
    result = deploy_fixtures("long-running", subset: ['undying-deployment.yml.erb']) do |fixtures|
      deployment = fixtures['undying-deployment.yml.erb']['Deployment'].first
      deployment['spec']['progressDeadlineSeconds'] = 2
      container = deployment['spec']['template']['spec']['containers'].first
      container['readinessProbe'] = { "exec" => { "command" => ['- ls'] } }
    end
    assert_deploy_failure(result)

    assert_logs_match_all([
      'Deployment/undying: TIMED OUT (limit: 420s)',
      'Deploy timed out due to progressDeadlineSeconds of 2 seconds'
    ])
  end

  def test_wait_false_ignores_non_priority_resource_failures
    # web depends on configmap so will not succeed deployed alone
    assert_deploy_success(deploy_fixtures("hello-cloud", subset: ["web.yml.erb"], wait: false))
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_deployment_up("web", replicas: 0) # it exists, but no pods available yet

    assert_logs_match_all([
      "Result: SUCCESS",
      "Deployed 3 resources",
      "Deploy result verification is disabled for this deploy."
    ], in_order: true)
  end

  def test_extra_bindings_should_be_rendered
    result = deploy_fixtures('collection-with-erb', subset: ["conf_map.yaml.erb"],
      bindings: { binding_test_a: 'binding_test_a', binding_test_b: 'binding_test_b' })
    assert_deploy_success(result)

    map = kubeclient.get_config_map('extra-binding', @namespace).data
    assert_equal 'binding_test_a', map['BINDING_TEST_A']
    assert_equal 'binding_test_b', map['BINDING_TEST_B']
  end

  def test_deploy_fails_if_required_binding_not_present
    assert_deploy_failure(deploy_fixtures('collection-with-erb', subset: ["conf_map.yaml.erb"]))
    assert_logs_match("Template 'conf_map.yaml.erb' cannot be rendered")
  end

  def test_long_running_deployment
    2.times do
      assert_deploy_success(deploy_fixtures('long-running'))
      assert_logs_match(%r{Service/multi-replica\s+Selects at least 1 pod})
    end

    pods = kubeclient.get_pods(namespace: @namespace, label_selector: 'name=undying,app=fixtures')
    assert_equal 4, pods.size

    count = count_by_revisions(pods)
    assert_equal [2, 2], count.values
    assert_logs_match(%r{Service/multi-replica\s+Selects at least 1 pod})
  end

  def test_create_and_update_secrets_from_ejson
    ejson_cloud = FixtureSetAssertions::EjsonCloud.new(@namespace)
    ejson_cloud.create_ejson_keys_secret
    assert_deploy_success(deploy_fixtures("ejson-cloud"))
    ejson_cloud.assert_all_up
    assert_logs_match_all([
      /Creating secret catphotoscom/,
      /Creating secret unused-secret/,
      /Creating secret monitoring-token/
    ])

    result = deploy_fixtures("ejson-cloud") do |fixtures|
      fixtures["secrets.ejson"]["kubernetes_secrets"]["unused-secret"]["data"] = { "_test" => "a" }
    end
    assert_deploy_success(result)
    ejson_cloud.assert_secret_present('unused-secret', { "test" => "a" }, managed: true)
    ejson_cloud.assert_web_resources_up
    assert_logs_match(/Updating secret unused-secret/)
  end

  def test_create_ejson_secrets_with_malformed_secret_data
    ejson_cloud = FixtureSetAssertions::EjsonCloud.new(@namespace)
    ejson_cloud.create_ejson_keys_secret

    malformed = { "_bad_data" => %w(foo bar) }
    result = deploy_fixtures("ejson-cloud") do |fixtures|
      fixtures["secrets.ejson"]["kubernetes_secrets"]["monitoring-token"]["data"] = malformed
    end
    assert_deploy_failure(result)
    assert_logs_match(/data for secret monitoring-token was invalid/)
  end

  def test_pruning_of_secrets_created_from_ejson
    ejson_cloud = FixtureSetAssertions::EjsonCloud.new(@namespace)
    ejson_cloud.create_ejson_keys_secret
    assert_deploy_success(deploy_fixtures("ejson-cloud"))
    ejson_cloud.assert_secret_present('unused-secret', managed: true)

    result = deploy_fixtures("ejson-cloud") do |fixtures|
      fixtures["secrets.ejson"]["kubernetes_secrets"].delete("unused-secret")
    end
    assert_deploy_success(result)
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
    assert_deploy_success(deploy_fixtures("ejson-cloud"))
    ejson_cloud.assert_all_up

    result = deploy_fixtures("ejson-cloud") do |fixtures|
      fixtures.delete("secrets.ejson")
    end
    assert_deploy_success(result)

    assert_logs_match_all([
      "Pruning secret unused-secret",
      "Pruning secret catphotoscom",
      "Pruning secret monitoring-token"
    ])

    ejson_cloud.refute_resource_exists('secret', 'unused-secret')
    ejson_cloud.refute_resource_exists('secret', 'catphotoscom')
    ejson_cloud.refute_resource_exists('secret', 'monitoring-token')
  end

  def test_deploy_result_logging_for_mixed_result_deploy
    forced_timeout = 20 # failure can take 10+s, which makes this test flake with shorter hard timeouts
    KubernetesDeploy::Deployment.any_instance.stubs(:timeout).returns(forced_timeout)
    result = deploy_fixtures("invalid", subset: ["bad_probe.yml", "init_crash.yml", "missing_volumes.yml"])
    assert_deploy_failure(result)
    # Debug info for bad probe timeout
    assert_logs_match_all([
      "Deployment/bad-probe: TIMED OUT (limit: #{forced_timeout}s)",
      "The following containers have not passed their readiness probes on at least one pod:",
      "http-probe must respond with a good status code at '/bad/ping/path'",
      "exec-probe must exit 0 from the following command: 'ls /bad/path'",
      "Final status: 1 replica, 1 updatedReplica, 1 unavailableReplica",
      "Scaled up replica set bad-probe-", # event
    ], in_order: true)
    refute_logs_match("sidecar must exit 0") # this container is ready

    # Debug info for missing volume timeout
    assert_logs_match_all([
      "Deployment/missing-volumes: TIMED OUT (limit: #{forced_timeout}s)",
      "Final status: 1 replica, 1 updatedReplica, 1 unavailableReplica",
      /FailedMount.*secrets "catphotoscom" not found/, # event
    ], in_order: true)

    # Debug info for failure
    assert_logs_match_all([
      "Deployment/init-crash: FAILED",
      "The following containers are in a state that is unlikely to be recoverable:",
      "init-crash-loop-back-off: Crashing repeatedly (exit 1). See logs for more information.",
      "Final status: 2 replicas, 2 updatedReplicas, 2 unavailableReplicas",
      "Scaled up replica set init-crash-", # event
      "ls: /not-a-dir: No such file or directory" # log
    ], in_order: true)

    # Excludes noisy events
    refute_logs_match(/Started container with id/)
    refute_logs_match(/Created container with id/)
    refute_logs_match(/Created pod/)
  end

  def test_failed_deploy_to_nonexistent_namespace
    original_ns = @namespace
    @namespace = 'this-certainly-should-not-exist'
    assert_deploy_failure(deploy_fixtures("hello-cloud", subset: ['configmap-data.yml']))
    assert_logs_match(/Result: FAILURE.*Namespace this-certainly-should-not-exist not found/m)
  ensure
    @namespace = original_ns
  end

  def test_failure_logs_from_unmanaged_pod_appear_in_summary_section
    result = deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "unmanaged-pod.yml.erb"]) do |fixtures|
      pod = fixtures["unmanaged-pod.yml.erb"]["Pod"].first
      container = pod["spec"]["containers"].first
      container["command"] = ["/some/bad/path"] # should throw an error
    end
    assert_deploy_failure(result)

    assert_logs_match_all([
      "Failed to deploy 1 priority resource",
      "hello-cloud: Failed to start (exit 127): Container command '/some/bad/path' not found or does not exist.",
      "Error response from daemon", # from an event
      "no such file or directory" # from logs
    ], in_order: true)
    refute_logs_match(/no such file or directory.*Result\: FAILURE/m) # logs not also displayed before summary
  end

  def test_unusual_timeout_output
    KubernetesDeploy::ConfigMap.any_instance.stubs(:deploy_succeeded?).returns(false)
    KubernetesDeploy::ConfigMap.any_instance.stubs(:timeout).returns(2)
    assert_deploy_failure(deploy_fixtures('hello-cloud', subset: ["configmap-data.yml"]))
    assert_logs_match("It is very unusual for this resource type to fail to deploy. Please try the deploy again.")
    assert_logs_match("Final status: Available")
  end

  # ref https://github.com/kubernetes/kubernetes/issues/26202
  def test_output_when_switching_labels_incorrectly
    assert_deploy_success(deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb"]))
    result = deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb"]) do |fixtures|
      web = fixtures["web.yml.erb"]["Deployment"].first
      web["spec"]["template"]["metadata"]["labels"] = { "name" => "foobar" }
    end
    assert_deploy_failure(result)

    assert_logs_match_all([
      "Command failed: apply -f",
      "WARNING: Any resources not mentioned in the error below were likely created/updated.",
      "Invalid templates: See error message",
      "> Error from kubectl:",
      /The Deployment "web" is invalid.*`selector` does not match template `labels`/
    ], in_order: true)
  end

  def test_can_deploy_deployment_with_zero_replicas
    result = deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb"]) do |fixtures|
      web = fixtures["web.yml.erb"]["Deployment"].first
      web["spec"]["replicas"] = 0
    end
    assert_deploy_success(result)

    pods = kubeclient.get_pods(namespace: @namespace)
    assert_equal 0, pods.length, "Pods were running from zero-replica deployment"

    assert_logs_match_all([
      %r{Service/web\s+Selects 0 pods},
      %r{Deployment/web\s+0 replicas}
    ])
  end

  def test_deploy_aborts_immediately_if_metadata_name_missing
    result = deploy_fixtures("hello-cloud", subset: ["configmap-data.yml"]) do |fixtures|
      definition = fixtures["configmap-data.yml"]["ConfigMap"].first
      definition["metadata"].delete("name")
    end
    assert_deploy_failure(result)

    assert_logs_match_all([
      "Result: FAILURE",
      "Template is missing required field metadata.name",
      "Rendered template content:",
      "kind: ConfigMap"
    ], in_order: true)
  end

  def test_deploy_aborts_immediately_if_unmanged_pod_spec_missing
    result = deploy_fixtures("hello-cloud", subset: ["unmanaged-pod.yml.erb"]) do |fixtures|
      definition = fixtures["unmanaged-pod.yml.erb"]["Pod"].first
      definition.delete("spec")
    end
    assert_deploy_failure(result)

    assert_logs_match_all([
      "Result: FAILURE",
      "Template is missing required field spec.containers",
      "Rendered template content:",
      "kind: Pod"
    ], in_order: true)
  end

  def test_success_detection_tolerates_out_of_band_deployment_scaling
    result = deploy_fixtures("hello-cloud", subset: ["web.yml.erb", "configmap-data.yml"]) do |fixtures|
      definition = fixtures["web.yml.erb"]["Deployment"].first
      definition["spec"].delete("replicas")
    end
    assert_deploy_success(result)
  end

  def test_output_when_unmanaged_pod_preexists
    result = deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "unmanaged-pod.yml.erb"]) do |fixtures|
      pod = fixtures["unmanaged-pod.yml.erb"]["Pod"].first
      pod["metadata"]["name"] = "oops-it-is-static"
    end
    assert_deploy_success(result)

    # Second deploy should fail because unmanaged pod already exists
    result = deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "unmanaged-pod.yml.erb"]) do |fixtures|
      pod = fixtures["unmanaged-pod.yml.erb"]["Pod"].first
      pod["metadata"]["name"] = "oops-it-is-static"
    end
    assert_deploy_failure(result)
    assert_logs_match("Unmanaged pods like Pod/oops-it-is-static must have unique names on every deploy")
  end

  def test_bad_container_on_daemon_sets_fails
    result = deploy_fixtures("hello-cloud", subset: ["daemon_set.yml"]) do |fixtures|
      daemon_set = fixtures['daemon_set.yml']['DaemonSet'].first
      container = daemon_set['spec']['template']['spec']['containers'].first
      container["image"] = "busybox"
      container["command"] = ["ls", "/not-a-dir"]
    end

    assert_deploy_failure(result)
    assert_logs_match_all([
      "DaemonSet/nginx: FAILED",
      "nginx: Crashing repeatedly (exit 1). See logs for more information.",
      "Final status: 1 currentNumberScheduled, 1 desiredNumberScheduled, 0 numberReady",
      "Events (common success events excluded):",
      "BackOff: Back-off restarting failed container",
      "Logs from container 'nginx' (last 250 lines shown):",
      "ls: /not-a-dir: No such file or directory"
    ], in_order: true)
  end

  def test_resource_quotas_are_deployed_first
    forced_timeout = 10
    KubernetesDeploy::Deployment.any_instance.stubs(:timeout).returns(forced_timeout)
    result = deploy_fixtures("resource-quota")
    assert_deploy_failure(result)
    assert_logs_match_all([
      "Predeploying priority resources",
      "Deploying ResourceQuota/resource-quotas (timeout: 30s)",
      "Deployment/web rollout timed out",
      "Successful resources",
      "ResourceQuota/resource-quotas",
      "Deployment/web: TIMED OUT (limit: 10s)",
      "failed quota: resource-quotas"
    ], in_order: true)

    rqs = kubeclient.get_resource_quotas(namespace: @namespace)
    assert_equal 1, rqs.length

    rq = rqs[0]
    assert_equal "resource-quotas", rq["metadata"]["name"]
    assert rq["spec"].present?
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
