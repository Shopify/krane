# frozen_string_literal: true
require 'integration_test_helper'

class KubernetesDeployTest < KubernetesDeploy::IntegrationTest
  def test_full_hello_cloud_set_deploy_succeeds
    assert_deploy_success(deploy_fixtures("hello-cloud"))
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_all_up

    assert_logs_match_all([
      "Deploying ConfigMap/hello-cloud-configmap-data (timeout: 30s)",
      %r{Deploying Pod/unmanaged-pod-[-\w]+ \(timeout: 60s\)}, # annotation timeout override
      "Hello from the command runner!", # unmanaged pod logs
      "Result: SUCCESS",
      "Successfully deployed 22 resources",
    ], in_order: true)

    num_ds = expected_daemonset_pod_count
    assert_logs_match_all([
      %r{ReplicaSet/bare-replica-set\s+1 replica, 1 availableReplica, 1 readyReplica},
      %r{Deployment/web\s+1 replica, 1 updatedReplica, 1 availableReplica},
      %r{Service/web\s+Selects at least 1 pod},
      %r{DaemonSet/ds-app\s+#{num_ds} updatedNumberScheduled, #{num_ds} desiredNumberScheduled, #{num_ds} numberReady},
      %r{StatefulSet/stateful-busybox},
      %r{Service/redis-external\s+Doesn't require any endpoint},
      "- Job/hello-job (timeout: 600s)",
      %r{Job/hello-job\s+(Succeeded|Started)},
    ])

    # Verify that success section isn't duplicated for predeployed resources
    assert_logs_match("Successful resources", 1)
    assert_logs_match(%r{ConfigMap/hello-cloud-configmap-data\s+Available}, 1)
  end

  def test_service_account_predeployed_before_unmanaged_pod
    # Add a valid service account in unmanaged pod
    service_account_name = "build-robot"
    result = deploy_fixtures("hello-cloud",
      subset: ["configmap-data.yml", "unmanaged-pod.yml.erb", "service-account.yml"]) do |fixtures|
      pod = fixtures["unmanaged-pod.yml.erb"]["Pod"].first
      pod["spec"]["serviceAccountName"] = service_account_name
      pod["spec"]["automountServiceAccountToken"] = false
    end
    # Expect the service account is deployed before the unmanaged pod
    assert_deploy_success(result)
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_configmap_data_present
    hello_cloud.assert_all_service_accounts_up
    hello_cloud.assert_unmanaged_pod_statuses("Succeeded")
    assert_logs_match_all([
      %r{Successfully deployed in \d.\ds: ServiceAccount/build-robot},
      %r{Successfully deployed in \d.\ds: Pod/unmanaged-pod-.*},
    ], in_order: true)
  end

  def test_role_and_role_binding_predeployed_before_unmanaged_pod
    result = deploy_fixtures(
      "hello-cloud",
      subset: [
        "configmap-data.yml",
        "unmanaged-pod.yml.erb",
        "role-binding.yml",
        "role.yml",
        "service-account.yml",
      ]
    )

    # Expect that role binding account is deployed before the unmanaged pod
    assert_deploy_success(result)
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_configmap_data_present
    hello_cloud.assert_all_service_accounts_up
    hello_cloud.assert_all_roles_up
    hello_cloud.assert_all_role_bindings_up
    hello_cloud.assert_unmanaged_pod_statuses("Succeeded")
    assert_logs_match_all([
      %r{Successfully deployed in \d.\ds: Role/role},
      %r{Successfully deployed in \d.\ds: RoleBinding/role-binding},
      %r{Successfully deployed in \d.\ds: Pod/unmanaged-pod-.*},
    ], in_order: true)
  end

  def test_pruning_works
    assert_deploy_success(deploy_fixtures("hello-cloud"))
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_all_up

    assert_deploy_success(deploy_fixtures("hello-cloud", subset: ["redis.yml"]))
    hello_cloud.assert_all_redis_resources_up
    hello_cloud.refute_configmap_data_exists
    hello_cloud.refute_unmanaged_pod_exists
    hello_cloud.refute_web_resources_exist
    expected_pruned = [
      prune_matcher("configmap", "", "hello-cloud-configmap-data"),
      prune_matcher("pod", "", "unmanaged-pod-"),
      prune_matcher("service", "", "web"),
      prune_matcher("resourcequota", "", "resource-quotas"),
      prune_matcher("deployment", "extensions", "web"),
      prune_matcher("ingress", "extensions", "web"),
      prune_matcher("daemonset", "extensions", "ds-app"),
      prune_matcher("statefulset", "apps", "stateful-busybox"),
      prune_matcher("job", "batch", "hello-job"),
      prune_matcher("poddisruptionbudget", "policy", "test"),
      prune_matcher("networkpolicy", "networking.k8s.io", "allow-all-network-policy"),
    ] # not necessarily listed in this order
    expected_msgs = [/Pruned 11 resources and successfully deployed 6 resources/]
    expected_pruned.map do |resource|
      expected_msgs << /The following resources were pruned:.*#{resource}/
    end
    assert_logs_match_all(expected_msgs)
  end

  def test_pruning_disabled
    assert_deploy_success(deploy_fixtures("hello-cloud", subset: ["configmap-data.yml"]))
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_configmap_data_present

    assert_deploy_success(deploy_fixtures("hello-cloud", subset: ["disruption-budgets.yml"], prune: false))
    hello_cloud.assert_configmap_data_present
    hello_cloud.assert_poddisruptionbudget
  end

  def test_refuses_deploy_to_protected_namespace_with_override_if_pruning_enabled
    generated_ns = @namespace
    @namespace = 'default'
    assert_deploy_failure(deploy_fixtures("hello-cloud", allow_protected_ns: true, prune: true))
    assert_logs_match_all([
      "Configuration invalid",
      "- Refusing to deploy to protected namespace 'default' with pruning enabled",
    ], in_order: true)
  ensure
    @namespace = generated_ns
  end

  def test_refuses_deploy_to_protected_namespace_without_override
    generated_ns = @namespace
    @namespace = 'default'
    assert_deploy_failure(deploy_fixtures("hello-cloud", prune: false))
    assert_logs_match_all([
      "Configuration invalid",
      "- Refusing to deploy to protected namespace",
    ], in_order: true)
  ensure
    @namespace = generated_ns
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
      "data" => { "foo" => "YmFy" },
    }

    result = deploy_fixtures("hello-cloud", subset: ["configmap-data.yml"]) do |fixtures|
      fixtures["secret.yml"] = { "Secret" => secret }
    end
    assert_deploy_success(result)

    live_secret = kubeclient.get_secret("test", @namespace)
    assert_equal({ foo: "YmFy" }, live_secret["data"].to_h)
  end

  def test_invalid_yaml_fails_fast
    assert_deploy_failure(deploy_raw_fixtures("invalid", subset: ["yaml-error.yml"]))
    assert_logs_match_all([
      "Failed to render and parse template",
      "Invalid template: yaml-error.yml",
      "mapping values are not allowed in this context",
      "> Template content:",
      "datapoint1: value1:",
    ], in_order: true)
  end

  def test_invalid_yaml_in_partial_prints_helpful_error
    assert_deploy_failure(deploy_raw_fixtures("invalid-partials"))
    included_from = "partial included from: include-invalid-partial.yml.erb"
    assert_logs_match_all([
      "Result: FAILURE",
      "Failed to render and parse template",
      %r{Invalid template: .*/partials/invalid.yml.erb \(#{included_from}\)},
      "> Error message:",
      %r{fixtures/partials/invalid.yml.erb\)\: mapping values are not allowed in this context},
      "> Template content:",
      "containers:",
      "- name: invalid-container",
      "notField: notval:",
    ], in_order: true)

    # make sure we're not displaying duplicate errors
    refute_logs_match("Template 'include-invalid-partial.yml.erb' cannot be rendered")
    assert_logs_match("Template content:", 1)
    assert_logs_match("Error message:", 1)
  end

  def test_missing_partial_correctly_identifies_invalid_template
    assert_deploy_failure(deploy_raw_fixtures("missing-partials", subset: ["parent-with-missing-child.yml.erb"]))

    assert_logs_match_all([
      "Result: FAILURE",
      "Failed to render and parse template",
      "Invalid template: parent-with-missing-child.yml.erb", # the thing with the invalid `partial` call in it
      "> Error message:",
      %r{Could not find partial 'does-not-exist' in any of .*fixture_dir[^/]*/partials:.*/partials},
      "> Template content:",
      "<%= partial 'does-not-exist' %>",
    ], in_order: true)
  end

  def test_missing_nested_partial_correctly_identifies_invalid_template_and_its_parents
    assert_deploy_failure(deploy_raw_fixtures("missing-partials", subset: ["parent-with-missing-grandchild.yml.erb"]))

    assert_logs_match_all([
      "Result: FAILURE",
      "Failed to render and parse template",
      "Invalid template: parent-with-missing-child (partial included from: parent-with-missing-grandchild.yml.erb)",
      "> Error message:",
      %r{Could not find partial 'does-not-exist' in any of .*fixture_dir[^/]*/partials:.*/partials},
      "> Template content:",
      "<%= partial 'does-not-exist' %>",
    ], in_order: true)
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
      "> Error message:",
      "error validating data: ValidationError(ConfigMap.metadata): \
unknown field \"myKey\" in io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta",
      "> Template content:",
      "      myKey: uhOh",
    ], in_order: true)
  end

  def test_dynamic_erb_collection_works
    assert_deploy_success(deploy_raw_fixtures("collection-with-erb",
      bindings: { binding_test_a: 'foo', binding_test_b: 'bar' }))

    deployments = v1beta1_kubeclient.get_deployments(namespace: @namespace)
    assert_equal(3, deployments.size)
    assert_equal(["web-one", "web-three", "web-two"], deployments.map { |d| d.metadata.name }.sort)
  end

  # The next three tests reproduce a k8s bug
  # The dry run should catch these problems, but it does not. Instead, apply fails.
  # https://github.com/kubernetes/kubernetes/issues/42057 shows how this manifested for a particular field,
  # and although that particular case has been fixed, other invalid specs still aren't caught until apply.
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
      "WARNING: Any resources not mentioned in the error(s) below were likely created/updated.",
      /Invalid template: Deployment-web.*\.yml/,
      "> Error message:",
      /Error from server \(Invalid\): error when creating.*Deployment\.?\w* "web" is invalid/,
      "> Template content:",
      "              name: http_test_is_really_long_and_invalid_chars",

      /Invalid template: Service-web.*\.yml/,
      "> Error message:",
      /Error from server \(Invalid\): error when creating.*Service "web" is invalid/,
      "> Template content:",
      "        targetPort: http_test_is_really_long_and_invalid_chars",
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
      "WARNING: Any resources not mentioned in the error(s) below were likely created/updated.",
      "Unidentified error(s):",
      '    The Service "web" is invalid:',
      'spec.ports[0].targetPort: Invalid value: "http_test_is_really_long_and_invalid_chars"',
    ], in_order: true)
  end

  def test_bad_container_image_on_unmanaged_pod_halts_and_fails_deploy
    result = deploy_fixtures("hello-cloud") do |fixtures|
      pod = fixtures["unmanaged-pod.yml.erb"]["Pod"].first
      pod["spec"]["containers"].first["image"] = "hello-world:thisImageIsBad"
    end
    assert_deploy_failure(result)
    assert_logs_match_all([
      "Failed to deploy 1 priority resource",
      %r{Pod\/unmanaged-pod-\w+-\w+: FAILED},
      "hello-cloud: Failed to pull image",
    ], in_order: true)

    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_unmanaged_pod_statuses("Pending")
    hello_cloud.assert_configmap_data_present # priority resource
    hello_cloud.refute_redis_resources_exist(expect_pvc: true) # pvc is priority resource
    hello_cloud.refute_web_resources_exist
  end

  def test_output_of_failed_unmanaged_pod
    result = deploy_fixtures("hello-cloud", subset: ["unmanaged-pod.yml.erb", "configmap-data.yml"]) do |fixtures|
      pod = fixtures["unmanaged-pod.yml.erb"]["Pod"].first
      pod["spec"]["containers"].first["command"] = ["/not/a/command"]
    end
    assert_deploy_failure(result)
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_unmanaged_pod_statuses("Failed")
    hello_cloud.refute_web_resources_exist

    assert_logs_match_all([
      "Failed to deploy 1 priority resource",
      "Pod status: Failed. The following containers encountered errors:",
      "> hello-cloud: Failed to start (exit 127):",
    ], in_order: true)
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
      "Failed to deploy 1 resource",
      "Deployment/web: FAILED",
      "The following containers are in a state that is unlikely to be recoverable:",
      /app: Failed to generate container configuration: secrets? \"monitoring-token\" not found/,
      "Final status: 3 replicas, 3 updatedReplicas, 3 unavailableReplicas",
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
      "Failed to deploy 1 resource",
      "Deployment/cannot-run: FAILED",
      "The following containers are in a state that is unlikely to be recoverable:",
      "container-cannot-run: Failed to pull image some-invalid-image:badtag.",
      "Did you wait for it to be built and pushed to the registry before deploying?",
    ], in_order: true)
  end

  def test_bad_init_container_on_deployment_fails_quickly
    assert_deploy_failure(deploy_fixtures("invalid", subset: ["init_crash.yml"]))
    assert_logs_match_all([
      "Deployment/init-crash: FAILED",
      "The following containers are in a state that is unlikely to be recoverable:",
      "init-crash-loop-back-off: Crashing repeatedly (exit 1). See logs for more information.",
      "this is a log from the crashing init container",
    ], in_order: true)
  end

  def test_crashing_container_on_deployment_fails_quickly
    assert_deploy_failure(deploy_fixtures("invalid", subset: ["crash_loop.yml"]))

    assert_logs_match_all([
      "Failed to deploy 1 resource",
      "Deployment/crash-loop: FAILED",
      "The following containers are in a state that is unlikely to be recoverable:",
      "crash-loop-back-off: Crashing repeatedly (exit 1). See logs for more information.",
      "this is a log from the crashing container",
    ], in_order: true)
  end

  def test_unrunnable_container_on_deployment_pod_fails_quickly
    assert_deploy_failure(deploy_fixtures("invalid", subset: ["cannot_run.yml"]))

    assert_logs_match_all([
      "Failed to deploy 1 resource",
      "Deployment/cannot-run: FAILED",
      "The following containers are in a state that is unlikely to be recoverable:",
      %r{container-cannot-run: Failed to start \(exit 127\): .*/some/bad/path},
      "Logs from container 'successful-init'",
      "Log from successful init container",
    ], in_order: true)
    assert_logs_match("no such file or directory")
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
      "hello-cloud: Failed to pull image hello-world:thisImageIsBad",
    ])
  end

  def test_deployment_with_progress_times_out_for_short_duration
    # The deployment adds a short progressDeadlineSeconds and attepts to deploy a container
    # which sleeps and cannot fulfill the readiness probe causing it to timeout
    result = deploy_fixtures("long-running", subset: ['undying-deployment.yml.erb']) do |fixtures|
      deployment = fixtures['undying-deployment.yml.erb']['Deployment'].first
      deployment['spec']['progressDeadlineSeconds'] = 10
      container = deployment['spec']['template']['spec']['containers'].first
      container['readinessProbe'] = { "exec" => { "command" => ['- ls'] } }
    end
    assert_deploy_failure(result, :timed_out)

    assert_logs_match_all([
      "Successfully deployed 1 resource and timed out waiting for 1 resource to deploy",
      'Deployment/undying: TIMED OUT (progress deadline: 10s)',
      'Timeout reason: ProgressDeadlineExceeded',
    ])
  end

  def test_deployment_with_timeout_override
    result = deploy_fixtures("long-running", subset: ['undying-deployment.yml.erb']) do |fixtures|
      deployment = fixtures['undying-deployment.yml.erb']['Deployment'].first
      deployment['spec']['progressDeadlineSeconds'] = 5
      deployment["metadata"]["annotations"] = {
        KubernetesDeploy::KubernetesResource::TIMEOUT_OVERRIDE_ANNOTATION => "10S",
      }
      container = deployment['spec']['template']['spec']['containers'].first
      container['readinessProbe'] = { "exec" => { "command" => ['- ls'] } }
    end
    assert_deploy_failure(result, :timed_out)
    assert_logs_match_all(KubernetesDeploy::KubernetesResource::STANDARD_TIMEOUT_MESSAGE.split("\n") +
      ["timeout override: 10s"])
  end

  def test_wait_false_ignores_non_priority_resource_failures
    # web depends on configmap so will not succeed deployed alone
    assert_deploy_success(deploy_fixtures("hello-cloud", subset: ["web.yml.erb"], wait: false))
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_deployment_up("web", replicas: 0) # it exists, but no pods available yet

    assert_logs_match_all([
      "Result: SUCCESS",
      "Deployed 3 resources",
      "Deploy result verification is disabled for this deploy.",
    ], in_order: true)
  end

  def test_extra_bindings_should_be_rendered
    result = deploy_fixtures('collection-with-erb', subset: ["conf_map.yaml.erb"],
      bindings: { binding_test_a: 'binding_test_a', binding_test_b: 'binding_test_b' })
    assert_deploy_success(result)

    map = kubeclient.get_config_map('extra-binding', @namespace).data
    assert_equal('binding_test_a', map['BINDING_TEST_A'])
    assert_equal('binding_test_b', map['BINDING_TEST_B'])
  end

  def test_deploy_fails_if_required_binding_not_present
    assert_deploy_failure(deploy_fixtures('collection-with-erb', subset: ["conf_map.yaml.erb"]))
    assert_logs_match_all([
      "Result: FAILURE",
      "Failed to render and parse template",
      "Invalid template: conf_map.yaml.erb",
      "> Error message:",
      "undefined local variable or method `binding_test_a'",
      "> Template content:",
      'BINDING_TEST_A: "<%= binding_test_a %>"',
    ], in_order: true)
  end

  def test_long_running_deployment
    2.times do |n|
      assert_deploy_success(deploy_fixtures('long-running', sha: "deploy#{n}"))
      assert_logs_match(%r{Service/multi-replica\s+Selects at least 1 pod})
    end

    pods = kubeclient.get_pods(namespace: @namespace, label_selector: 'name=undying,app=fixtures')
    by_revision = pods.group_by { |pod| pod.spec.containers.first.env.find { |var| var.name == "GITHUB_REV" }.value }
    by_revision.each do |rev, rev_pods|
      statuses = rev_pods.map { |pod| pod.status.to_h }
      assert_equal 2, rev_pods.length, "#{rev} had #{rev_pods.length} pods (wanted 2). Statuses:\n#{statuses}"
    end
    assert_logs_match(%r{Service/multi-replica\s+Selects at least 1 pod})
  end

  def test_create_ejson_secrets_with_malformed_secret_data
    ejson_cloud = FixtureSetAssertions::EjsonCloud.new(@namespace)
    ejson_cloud.create_ejson_keys_secret

    malformed = { "_bad_data" => %w(foo bar) }
    result = deploy_fixtures("ejson-cloud") do |fixtures|
      fixtures["secrets.ejson"]["kubernetes_secrets"]["monitoring-token"]["data"] = malformed
    end
    assert_deploy_failure(result)
    assert_logs_match("Creation of kubernetes secrets from ejson failed: data for secret monitoring-token was invalid")
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
      "Pruning secret monitoring-token",
    ])

    ejson_cloud.refute_resource_exists('secret', 'unused-secret')
    ejson_cloud.refute_resource_exists('secret', 'catphotoscom')
    ejson_cloud.refute_resource_exists('secret', 'monitoring-token')
  end

  def test_can_deploy_template_dir_with_only_secrets_ejson
    ejson_cloud = FixtureSetAssertions::EjsonCloud.new(@namespace)
    ejson_cloud.create_ejson_keys_secret
    assert_deploy_success(deploy_fixtures("ejson-cloud", subset: ["secrets.ejson"]))
    assert_logs_match_all([
      "Deploying kubernetes secrets from secrets.ejson",
      "Result: SUCCESS",
      %r{Created/updated \d+ secrets},
    ], in_order: true)
  end

  def test_deploy_result_logging_for_mixed_result_deploy
    subset = ["bad_probe.yml", "init_crash.yml", "missing_volumes.yml", "config_map.yml"]
    result = deploy_fixtures("invalid", subset: subset) do |f|
      f["bad_probe.yml"]["Deployment"].first["spec"]["progressDeadlineSeconds"] = 20
    end

    assert_deploy_failure(result)
    assert_logs_match_all([
      "Successfully deployed 1 resource, timed out waiting for 2 resources to deploy, and failed to deploy 1 resource",
      "Successful resources",
      %r{ConfigMap/test\s+Available},
    ], in_order: true)

    start_bad_probe_logs = [
      %r{Deployment/bad-probe: TIMED OUT \(progress deadline: \d+s\)},
      "Timeout reason: ProgressDeadlineExceeded",
    ]
    end_bad_probe_logs = ["Scaled up replica set bad-probe-"] # event

    # Debug info for bad probe timeout
    assert_logs_match_all(start_bad_probe_logs + [
      /Latest ReplicaSet: bad-probe-\w+/,
      "The following containers have not passed their readiness probes on at least one pod:",
      "http-probe must respond with a good status code at '/bad/ping/path'",
      "exec-probe must exit 0 from the following command: 'test 0 -eq 1'",
      "Final status: 1 replica, 1 updatedReplica, 1 unavailableReplica",
    ] + end_bad_probe_logs, in_order: true)
    refute_logs_match("sidecar must exit 0") # this container is ready

    # Debug info for missing volume timeout
    assert_logs_match_all([
      %r{Deployment/missing-volumes: TIMED OUT \(progress deadline: \d+s\)},
      "Timeout reason: ProgressDeadlineExceeded",
      /Latest ReplicaSet: missing-volumes-\w+/,
      "Final status: 1 replica, 1 updatedReplica, 1 unavailableReplica",
      /FailedMount.*secrets? "catphotoscom" not found/, # event
    ], in_order: true)

    # Debug info for failure
    assert_logs_match_all([
      "Deployment/init-crash: FAILED",
      /Latest ReplicaSet: init-crash-\w+/,
      "The following containers are in a state that is unlikely to be recoverable:",
      "init-crash-loop-back-off: Crashing repeatedly (exit 1). See logs for more information.",
      "Final status: 1 replica, 1 updatedReplica, 1 unavailableReplica",
      "Scaled up replica set init-crash-", # event
      "this is a log from the crashing init container",
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
    assert_logs_match(/Result: FAILURE.*namespaces "this-certainly-should-not-exist" not found/m)
  ensure
    @namespace = original_ns
  end

  def test_failure_logs_from_unmanaged_pod_appear_in_summary_section
    result = deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "unmanaged-pod.yml.erb"]) do |fixtures|
      pod = fixtures["unmanaged-pod.yml.erb"]["Pod"].first
      container = pod["spec"]["containers"].first
      container["command"] = ["sh", "-c", "/some/bad/path"] # should throw an error
    end
    assert_deploy_failure(result)

    assert_logs_match_all([
      "Failed to deploy 1 priority resource",
      "Logs from container 'hello-cloud':",
      "sh: /some/bad/path: not found" # from logs
    ], in_order: true)
    refute_logs_match(/no such file or directory.*Result\: FAILURE/m) # logs not also displayed before summary
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
      "WARNING: Any resources not mentioned in the error(s) below were likely created/updated.",
      "Unidentified error(s):",
      /The Deployment "web" is invalid.*`selector` does not match template `labels`/,
    ], in_order: true)
  end

  def test_scale_existing_deployment_down_to_zero
    pod_name = nil
    pod_status = "Running"
    # Create a deployement with 1 pod
    source = 1
    result = deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb"]) do |fixtures|
      web = fixtures["web.yml.erb"]["Deployment"].first
      web["spec"]["replicas"] = source
      # Disable grace period in deleting pods to speed up test
      web["spec"]["template"]["spec"]["terminationGracePeriodSeconds"] = 0
      pod_name = web["spec"]["template"]["metadata"]["labels"]["name"]
    end
    assert_deploy_success(result)
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_pod_status(pod_name, pod_status, source)
    # Scale down to 0 pod
    target = 0
    result = deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb"]) do |fixtures|
      web = fixtures["web.yml.erb"]["Deployment"].first
      web["spec"]["replicas"] = target
      web["spec"]["template"]["spec"]["terminationGracePeriodSeconds"] = 0
    end
    assert_deploy_success(result)
    hello_cloud.assert_pod_status(pod_name, pod_status, target)

    assert_logs_match_all([
      %r{Service/web\s+Selects at least 1 pod},
      %r{Deployment/web\s+1 replica, 1 updatedReplica, 1 availableReplica},
      %r{Service/web\s+Doesn't require any endpoint},
      %r{Deployment/web\s+0 replicas},
    ], in_order: true)
  end

  def test_can_deploy_deployment_with_zero_replicas
    result = deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb"]) do |fixtures|
      web = fixtures["web.yml.erb"]["Deployment"].first
      web["spec"]["replicas"] = 0
    end
    assert_deploy_success(result)

    pods = kubeclient.get_pods(namespace: @namespace)
    assert_equal(0, pods.length, "Pods were running from zero-replica deployment")

    assert_logs_match_all([
      %r{Service/web\s+Doesn't require any endpoint},
      %r{Deployment/web\s+0 replicas},
    ])
  end

  def test_deploy_successful_with_partial_availability
    result = deploy_fixtures("slow-cloud", sha: "deploy1")
    assert_deploy_success(result)

    result = deploy_fixtures("slow-cloud", sha: "deploy2") do |fixtures|
      dep = fixtures["web.yml.erb"]["Deployment"].first
      container = dep["spec"]["template"]["spec"]["containers"].first
      container["readinessProbe"] = {
        "exec" => { "command" => %w(sleep 5) },
        "timeoutSeconds" => 6,
      }
    end
    assert_deploy_success(result)

    new_pods = kubeclient.get_pods(namespace: @namespace, label_selector: 'name=web,app=slow-cloud,sha=deploy2')
    assert(new_pods.length >= 1, "Expected at least one new pod, saw #{new_pods.length}")

    new_ready_pods = new_pods.select do |pod|
      pod.status.phase == "Running" &&
      pod.status.conditions.any? { |condition| condition["type"] == "Ready" && condition["status"] == "True" }
    end
    assert_equal(1, new_ready_pods.length, "Expected exactly one new pod to be ready, saw #{new_ready_pods.length}")
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
      "kind: ConfigMap",
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
      "kind: Pod",
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
    assert_deploy_failure(deploy_fixtures("invalid", subset: ["crash_loop_daemon_set.yml"]))
    num_ds = expected_daemonset_pod_count
    assert_logs_match_all([
      "Failed to deploy 1 resource",
      "DaemonSet/crash-loop: FAILED",
      "crash-loop-back-off: Crashing repeatedly (exit 1). See logs for more information.",
      "Final status: #{num_ds} updatedNumberScheduled, #{num_ds} desiredNumberScheduled, 0 numberReady",
      "Events (common success events excluded):",
      "BackOff: Back-off restarting failed container",
      "Logs from container 'crash-loop-back-off':",
      "this is a log from the crashing container",
    ], in_order: true)
  end

  def test_bad_container_on_stateful_sets_fails_with_rolling_update
    result = deploy_fixtures("hello-cloud", subset: ["stateful_set.yml"]) do |fixtures|
      stateful_set = fixtures['stateful_set.yml']['StatefulSet'].first
      stateful_set['spec']['updateStrategy'] = { 'type' => 'RollingUpdate' }
      container = stateful_set['spec']['template']['spec']['containers'].first
      container["image"] = "busybox"
      container["command"] = ["ls", "/not-a-dir"]
    end

    assert_deploy_failure(result)
    assert_logs_match_all([
      "Failed to deploy 1 resource",
      "StatefulSet/stateful-busybox: FAILED",
      "app: Crashing repeatedly (exit 1). See logs for more information.",
      "Events (common success events excluded):",
      %r{\[Pod/stateful-busybox-\d\]	BackOff: Back-off restarting failed container},
      "Logs from container 'app':",
      "ls: /not-a-dir: No such file or directory",
    ], in_order: true)
  end

  def test_on_delete_stateful_sets_are_not_monitored
    result = deploy_fixtures("hello-cloud", subset: ["stateful_set.yml"])

    assert_deploy_success(result)
    assert_logs_match_all([
      "WARNING: Your StatefulSet's updateStrategy is set to OnDelete",
      "Successful resources",
      "StatefulSet/stateful-busybox",
    ], in_order: true)
  end

  def test_rolling_update_stateful_sets_are_monitored
    result = deploy_fixtures("hello-cloud", subset: ["stateful_set.yml"]) do |fixtures|
      stateful_set = fixtures['stateful_set.yml']['StatefulSet'].first
      stateful_set['spec']['updateStrategy'] = { 'type' => 'RollingUpdate' }
    end

    assert_deploy_success(result)
    assert_logs_match_all([
      "Successfully deployed",
      "Successful resources",
      %r{StatefulSet/stateful-busybox\s+2 replicas, 2 readyReplicas, 2 currentReplicas},
    ], in_order: true)
  end

  def test_resource_quotas_are_deployed_first
    result = deploy_fixtures("resource-quota")
    assert_deploy_failure(result, :timed_out)
    assert_logs_match_all([
      "Predeploying priority resources",
      "Deploying ResourceQuota/resource-quotas (timeout: 30s)",
      "Deployment/web rollout timed out",
      "Successfully deployed 1 resource and timed out waiting for 1 resource to deploy",
      "Successful resources",
      "ResourceQuota/resource-quotas",
      %r{Deployment/web: TIMED OUT \(progress deadline: \d+s\)},
      "Timeout reason: ProgressDeadlineExceeded",
      "failed quota: resource-quotas" # from an event
    ], in_order: true)

    rqs = kubeclient.get_resource_quotas(namespace: @namespace)
    assert_equal(1, rqs.length)

    rq = rqs[0]
    assert_equal("resource-quotas", rq["metadata"]["name"])
    assert(rq["spec"].present?)
  end

  def test_ejson_secrets_respects_no_prune_flag
    ejson_cloud = FixtureSetAssertions::EjsonCloud.new(@namespace)
    ejson_cloud.create_ejson_keys_secret
    assert_deploy_success(deploy_fixtures("ejson-cloud"))
    ejson_cloud.assert_secret_present('unused-secret', managed: true)

    result = deploy_fixtures("ejson-cloud", prune: false) do |fixtures|
      fixtures["secrets.ejson"]["kubernetes_secrets"].delete("unused-secret")
    end
    assert_deploy_success(result)

    # The removed secret was not pruned
    ejson_cloud.assert_secret_present('unused-secret', managed: true)
    # The remaining secrets also exist
    ejson_cloud.assert_secret_present('monitoring-token', managed: true)
    ejson_cloud.assert_secret_present('catphotoscom', type: 'kubernetes.io/tls', managed: true)
    ejson_cloud.assert_secret_present('ejson-keys', managed: false)
  end

  def test_partials
    assert_deploy_success(deploy_raw_fixtures("test-partials", bindings: { 'supports_partials' => 'true' }))
    assert_logs_match_all([
      "log from pod1",
      "log from pod2",
      "Successfully deployed 6 resources",
    ], in_order: false)

    map = kubeclient.get_config_map('config-for-pod1', @namespace).data
    assert_equal('true', map['supports_partials'])

    map = kubeclient.get_config_map('independent-configmap', @namespace).data
    assert_equal('renderer test', map['value'])
  end

  def test_roll_back_a_bad_deploy
    result = deploy_fixtures("invalid", subset: ["cannot_run.yml"], sha: "REVA") do |fixtures|
      container = fixtures["cannot_run.yml"]["Deployment"].first["spec"]["template"]["spec"]["containers"].first
      container["command"] = %w(sleep 8000)
    end
    assert_deploy_success(result)
    original_rs = v1beta1_kubeclient.get_replica_sets(namespace: @namespace).first
    original_rs_uid = original_rs["metadata"]["uid"]
    assert(original_rs_uid.present?)
    assert_equal(2, original_rs["status"]["availableReplicas"])

    # Bad deploy
    assert_deploy_failure(deploy_fixtures("invalid", subset: ["cannot_run.yml"], sha: "REVB"))

    # Rollback
    result = deploy_fixtures("invalid", subset: ["cannot_run.yml"], sha: "REVA") do |fixtures|
      container = fixtures["cannot_run.yml"]["Deployment"].first["spec"]["template"]["spec"]["containers"].first
      container["command"] = %w(sleep 8000)
    end
    assert_deploy_success(result)

    all_rs = v1beta1_kubeclient.get_replica_sets(namespace: @namespace)
    assert_equal(2, all_rs.length, "Test premise failure: Rollback created a new RS")
    original_rs = all_rs.find { |rs| rs["metadata"]["uid"] == original_rs_uid }
    assert_equal(2, original_rs["status"]["availableReplicas"])
  end

  def test_deployment_with_recreate_strategy
    2.times do
      result = deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb"]) do |fixtures|
        deployment = fixtures["web.yml.erb"]["Deployment"].first
        deployment["spec"]["strategy"] = { "type" => "Recreate" }
        # if this is > 0, the test goes from taking 10s to taking 1m+. Original pod sticks in Terminating.
        deployment["spec"]["template"]["spec"]["terminationGracePeriodSeconds"] = 0
      end
      assert_deploy_success(result)
    end
  end

  def test_cronjobs_can_be_deployed
    assert_deploy_success(deploy_fixtures("cronjobs"))
    cronjobs = FixtureSetAssertions::CronJobs.new(@namespace)
    cronjobs.assert_cronjob_present("my-cronjob")
  end

  def test_jobs_can_fail
    fixtures = deploy_fixtures("hello-cloud", subset: ["job.yml"]) do |f|
      spec = f["job.yml"]["Job"].first["spec"]
      spec["backoffLimit"] = 1
      spec["activeDeadlineSeconds"] = 1
      spec["template"]["spec"]["containers"].first["command"] = %w(/not/a/command)
    end

    assert_deploy_failure(fixtures)
    assert_logs_match_all([
      "Deploying Job/hello-job (timeout: 600s)",
      "Result: FAILURE",
      "Job/hello-job: FAILED",
      "Final status: Failed",
      %r{\[Job/hello-job\]	DeadlineExceeded: Job was active longer than specified deadline \(\d+ events\)},
    ])
  end

  def test_resource_watcher_reports_failed_after_timeout
    result = deploy_fixtures(
      "invalid",
      subset: ["bad_probe.yml", "cannot_run.yml", "missing_volumes.yml", "config_map.yml"],
      max_watch_seconds: 20
    ) do |f|
      bad_probe = f["bad_probe.yml"]["Deployment"].first
      bad_probe["spec"]["progressDeadlineSeconds"] = 5
      f["missing_volumes.yml"]["Deployment"].first["spec"]["progressDeadlineSeconds"] = 25
      f["cannot_run.yml"]["Deployment"].first["spec"]["replicas"] = 1
    end
    assert_deploy_failure(result)

    bad_probe_timeout = "Deployment/bad-probe: TIMED OUT (progress deadline: 5s)"

    assert_logs_match_all([
      "Successfully deployed 1 resource, timed out waiting for 2 resources to deploy, and failed to deploy 1 resource",
      "Successful resources",
      "ConfigMap/test",
      "Deployment/cannot-run: FAILED",
      bad_probe_timeout,
      "Deployment/missing-volumes: GLOBAL WATCH TIMEOUT (20 seconds)",
    ])
  end

  def test_resource_watcher_raises_after_timeout_seconds
    result = deploy_fixtures("long-running", subset: ['undying-deployment.yml.erb'], max_watch_seconds: 5) do |fixtures|
      deployment = fixtures['undying-deployment.yml.erb']['Deployment'].first
      deployment['spec']['progressDeadlineSeconds'] = 100
      container = deployment['spec']['template']['spec']['containers'].first
      container['readinessProbe'] = { "exec" => { "command" => ['- ls'] } }
    end

    assert_deploy_failure(result, :timed_out)
    assert_logs_match_all([
      "Successfully deployed 1 resource and timed out waiting for 1 resource to deploy",
      "Successful resources",
      "Service/multi-replica",
      "Deployment/undying: GLOBAL WATCH TIMEOUT (5 seconds)",
      "If you expected it to take longer than 5 seconds for your deploy to roll out, increase --max-watch-seconds.",
    ], in_order: true)
  end

  def test_friendly_error_on_misidentified_erb_file
    assert_deploy_failure(deploy_raw_fixtures('invalid', subset: ['wrong-extension-erb.yml']))
    assert_logs_match_all([
      "Result: FAILURE",
      "Invalid template: wrong-extension-erb.yml",
      "Template is not a valid Kubernetes manifest",
      "> Template content:",
      "<% (0..2).each do |n| %>",
    ], in_order: true)
  end

  def test_raise_on_yaml_missing_kind
    result = deploy_fixtures("invalid-resources", subset: ["missing_kind.yml"])
    assert_deploy_failure(result)
    assert_logs_match_all([
      "Invalid template: missing_kind.yml",
      "> Error message:",
      "Template missing 'Kind'",
      "> Template content:",
      "---",
      "apiVersion: v1",
      "metadata:",
      "  name: test",
      "data:",
      "  datapoint: value1",
    ], in_order: true)
  end

  def test_hpa_can_be_successful
    assert_deploy_success(deploy_fixtures("hpa"))
    assert_logs_match_all([
      "Deploying resources:",
      "HorizontalPodAutoscaler/hello-hpa (timeout: 180s)",
      %r{HorizontalPodAutoscaler/hello-hpa\s+Configured},
    ])
  end

  def test_hpa_can_be_pruned
    assert_deploy_success(deploy_fixtures("hpa"))
    assert_deploy_success(deploy_fixtures("hpa", subset: ["deployment.yml"]))
    assert_logs_match_all([
      /The following resources were pruned: #{prune_matcher("horizontalpodautoscaler", "autoscaling", "hello-hpa")}/,
    ])
  end

  def test_not_apply_resource_can_be_pruned
    pod_disruption_budget_matcher = prune_matcher("poddisruptionbudget", "policy", "test")
    assert_deploy_success(deploy_fixtures("hello-cloud", subset: %w(disruption-budgets.yml configmap-data.yml)))
    assert_deploy_success(deploy_fixtures("hello-cloud", subset: %w(configmap-data.yml)))
    assert_logs_match_all([
      /The following resources were pruned: #{pod_disruption_budget_matcher}/,
    ])
  end

  def test_no_revision
    result = deploy_fixtures('hello-cloud', subset: ["configmap-data.yml"], sha: nil)
    assert_deploy_success(result)
  end

  def test_network_policies_are_deployed_first
    deploy_fixtures('hello-cloud', subset: ['network_policy.yml'])
    assert_logs_match_all([
      "Predeploying priority resources",
      "Deploying NetworkPolicy/allow-all-network-policy (timeout: 30s)",
      "Successfully deployed 1 resource",
      "Successful resources",
      "NetworkPolicy/allow-all-network-policy",
    ], in_order: true)
  end

  def test_default_config_file
    result = deploy_fixtures('hello-cloud', subset: ["configmap-data.yml"], kubeconfig: nil)
    assert_deploy_success(result)
  end

  def test_unreachable_context
    kubectl_instance = build_kubectl(
      kubeconfig: File.join(__dir__, '../fixtures/kube-config/dummy_config.yml'),
      timeout: '0.1s'
    )
    result = deploy_fixtures('hello-cloud', kubectl_instance: kubectl_instance)
    assert_deploy_failure(result)
    assert_logs_match_all([
      'The following command failed (attempt 1/1): kubectl version',
      'Unable to connect to the server',
      'Unable to connect to the server',
      'Unable to connect to the server',
      'Result: FAILURE',
      "Failed to reach server for #{TEST_CONTEXT}",
    ], in_order: true)
  end

  def test_missing_configuration_file
    config_file = File.join(__dir__, '../fixtures/kube-config/unknown_config.yml')
    result = deploy_fixtures('hello-cloud', kubeconfig: config_file)
    assert_deploy_failure(result)
    assert_logs_match_all([
      'Result: FAILURE',
      'Configuration invalid',
      "Kube config not found at #{config_file}",
    ], in_order: true)
  end

  def test_multiple_configuration_files
    result = deploy_fixtures('hello-cloud', kubeconfig: " : ")
    assert_deploy_failure(result)
    assert_logs_match_all([
      'Result: FAILURE',
      'Configuration invalid',
      "Kube config file name(s) not set in $KUBECONFIG",
    ], in_order: true)
    reset_logger

    default_config = "#{Dir.home}/.kube/config"
    extra_config = File.join(__dir__, '../fixtures/kube-config/dummy_config.yml')
    result = deploy_fixtures(
      'hello-cloud',
      subset: ["configmap-data.yml"],
      kubeconfig: "#{default_config}:#{extra_config}"
    )
    assert_deploy_success(result)
  end

  private

  def expected_daemonset_pod_count
    nodes = kubeclient.get_nodes
    return 1 if nodes.one?
    nodes.count do |node|
      !node.metadata.labels.to_h.keys.include?(:"node-role.kubernetes.io/master")
    end
  end
end
