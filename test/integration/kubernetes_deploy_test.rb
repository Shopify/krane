# frozen_string_literal: true
require 'integration_test_helper'

class KubernetesDeployTest < KubernetesDeploy::IntegrationTest
  def test_full_hello_cloud_set_deploy_succeeds
    assert_deploy_success(deploy_fixtures("hello-cloud"))
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_all_up

    assert_logs_match_all([
      "All required parameters and files are present",
      "Deploying ConfigMap/hello-cloud-configmap-data (timeout: 30s)",
      /Deploying resources:/,
      %r{- Pod/unmanaged-pod-1-[-\w]+ \(timeout: 60s\)}, # annotation timeout override
      %r{- Pod/unmanaged-pod-2-[-\w]+ \(timeout: 60s\)}, # annotation timeout override
      "Hello from the command runner!", # unmanaged pod logs
      "Result: SUCCESS",
      "Successfully deployed 25 resources",
    ], in_order: true)
    refute_logs_match(/Using resource selector/)

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
      subset: ["configmap-data.yml", "unmanaged-pod-1.yml.erb", "service-account.yml"]) do |fixtures|
      pod = fixtures["unmanaged-pod-1.yml.erb"]["Pod"].first
      pod["spec"]["serviceAccountName"] = service_account_name
      pod["spec"]["automountServiceAccountToken"] = false
    end
    # Expect the service account is deployed before the unmanaged pod
    assert_deploy_success(result)
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_configmap_data_present
    hello_cloud.assert_all_service_accounts_up
    hello_cloud.assert_unmanaged_pod_statuses("Succeeded", 1)
    assert_logs_match_all([
      %r{Successfully deployed in \d.\ds: ServiceAccount/build-robot},
      %r{Successfully deployed in \d+.\ds: Pod/unmanaged-pod-.*},
    ], in_order: true)
  end

  def test_role_and_role_binding_predeployed_before_unmanaged_pod
    result = deploy_fixtures(
      "hello-cloud",
      subset: [
        "configmap-data.yml",
        "unmanaged-pod-1.yml.erb",
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
    hello_cloud.assert_unmanaged_pod_statuses("Succeeded", 1)
    assert_logs_match_all([
      %r{Successfully deployed in \d.\ds: Role/role},
      %r{Successfully deployed in \d.\ds: RoleBinding/role-binding},
      %r{Successfully deployed in \d+.\ds: Pod/unmanaged-pod-1-.*},
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
      prune_matcher("service", "", "stateful-busybox"),
      prune_matcher("resourcequota", "", "resource-quotas"),
      prune_matcher("deployment", "extensions", "web"),
      prune_matcher("ingress", "extensions", "web"),
      prune_matcher("daemonset", "extensions", "ds-app"),
      prune_matcher("statefulset", "apps", "stateful-busybox"),
      prune_matcher("job", "batch", "hello-job"),
      prune_matcher("poddisruptionbudget", "policy", "test"),
      prune_matcher("networkpolicy", "networking.k8s.io", "allow-all-network-policy"),
      prune_matcher("secret", "", "hello-secret"),
      prune_matcher("replicaset", "extensions", "bare-replica-set"),
      prune_matcher("serviceaccount", "", "build-robot"),
      prune_matcher("podtemplate", "", "hello-cloud-template-runner"),
      prune_matcher("role", "rbac.authorization.k8s.io", "role"),
      prune_matcher("rolebinding", "rbac.authorization.k8s.io", "role-binding"),
    ] # not necessarily listed in this order
    expected_msgs = [/Pruned 19 resources and successfully deployed 6 resources/]
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

  def test_selector
    # Deploy the same thing twice with a different selector
    assert_deploy_success(deploy_fixtures("branched",
      bindings: { "branch" => "master" },
      selector: KubernetesDeploy::LabelSelector.parse("branch=master")))
    assert_logs_match("Using resource selector branch=master")
    assert_deploy_success(deploy_fixtures("branched",
      bindings: { "branch" => "staging" },
      selector: KubernetesDeploy::LabelSelector.parse("branch=staging")))
    assert_logs_match("Using resource selector branch=staging")
    deployments = v1beta1_kubeclient.get_deployments(namespace: @namespace, label_selector: "app=branched")

    assert_equal(2, deployments.size)
    assert_equal(%w(master staging), deployments.map { |d| d.metadata.labels.branch }.sort)

    # Run again without selector to verify pruning works
    assert_deploy_success(deploy_fixtures("branched", bindings: { "branch" => "master" }))
    deployments = v1beta1_kubeclient.get_deployments(namespace: @namespace, label_selector: "app=branched")
    # Filter out pruned resources pending deletion
    deployments.select! { |deployment| deployment.metadata.deletionTimestamp.nil? }

    assert_equal(1, deployments.size)
    assert_equal("master", deployments.first.metadata.labels.branch)
  end

  def test_mismatched_selector
    assert_deploy_failure(deploy_fixtures("branched",
      bindings: { "branch" => "master" },
      selector: KubernetesDeploy::LabelSelector.parse("branch=staging")))
    assert_logs_match_all([
      /Using resource selector branch=staging/,
      /Template validation failed/,
      /Invalid template: Deployment/,
      /selector branch=staging does not match labels app=branched,branch=master/,
      /> Template content:/,
    ], in_order: true)
  end

  def test_mismatched_selector_on_replace_resource_without_labels
    assert_deploy_failure(deploy_fixtures("hello-cloud",
      subset: %w(disruption-budgets.yml),
      selector: KubernetesDeploy::LabelSelector.parse("branch=staging")))
    assert_logs_match_all([
      /Using resource selector branch=staging/,
      /Template validation failed/,
      /Invalid template: PodDisruptionBudget/,
      /selector branch=staging passed in, but no labels were defined/,
      /> Template content:/,
    ], in_order: true)
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
    resource_kind = "ReplicationController"
    resource_name = "test-rc"

    result = deploy_fixtures("unrecognized-type")
    assert_deploy_success(result)

    # This will raise an exception if the resource is missing
    kubeclient.get_entity(resource_kind.downcase.pluralize, resource_name, @namespace)
    assert_logs_match(/Don't know how to monitor resources of type #{resource_kind}/)
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

  def test_output_of_failed_unmanaged_pod
    result = deploy_fixtures("hello-cloud", subset: ["unmanaged-pod-1.yml.erb", "configmap-data.yml"]) do |fixtures|
      pod = fixtures["unmanaged-pod-1.yml.erb"]["Pod"].first
      pod["spec"]["containers"].first["command"] = ["/not/a/command"]
    end
    assert_deploy_failure(result)
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_unmanaged_pod_statuses("Failed", 1)
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
      pod = fixtures["unmanaged-pod-1.yml.erb"]["Pod"].first
      pod["spec"]["containers"].first["image"] = "hello-world:thisImageIsBad"
    end
    assert_deploy_failure(result)
    assert_logs_match_all([
      "Failed to deploy 1 priority resource",
      %r{Pod\/unmanaged-pod-1-\w+-\w+: FAILED},
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

  def test_deployment_with_timeout_override_deprecated
    result = deploy_fixtures("long-running", subset: ['undying-deployment.yml.erb']) do |fixtures|
      deployment = fixtures['undying-deployment.yml.erb']['Deployment'].first
      deployment['spec']['progressDeadlineSeconds'] = 5
      deployment["metadata"]["annotations"] = {
        KubernetesDeploy::KubernetesResource::TIMEOUT_OVERRIDE_ANNOTATION_DEPRECATED => "10S",
      }
      container = deployment['spec']['template']['spec']['containers'].first
      container['readinessProbe'] = { "exec" => { "command" => ['- ls'] } }
    end
    assert_deploy_failure(result, :timed_out)
    assert_logs_match_all(KubernetesDeploy::KubernetesResource::STANDARD_TIMEOUT_MESSAGE.split("\n") +
      ["timeout override: 10s"])
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
    assert_logs_match(
      "Generation of kubernetes secrets from ejson failed: data for secret monitoring-token was invalid"
    )
  end

  def test_pruning_of_secrets_created_from_ejson
    ejson_cloud = FixtureSetAssertions::EjsonCloud.new(@namespace)
    ejson_cloud.create_ejson_keys_secret
    assert_deploy_success(deploy_fixtures("ejson-cloud"))
    ejson_cloud.assert_secret_present('unused-secret', ejson: true)

    result = deploy_fixtures("ejson-cloud") do |fixtures|
      fixtures["secrets.ejson"]["kubernetes_secrets"].delete("unused-secret")
    end
    assert_deploy_success(result)
    assert_logs_match(%r{The following resources were pruned:.*secret( "|\/)unused-secret})

    # The removed secret was pruned
    ejson_cloud.refute_resource_exists('secret', 'unused-secret')
    # The remaining secrets exist
    ejson_cloud.assert_secret_present('monitoring-token', ejson: true)
    ejson_cloud.assert_secret_present('catphotoscom', type: 'kubernetes.io/tls', ejson: true)
    # The unmanaged secret was not pruned
    ejson_cloud.assert_secret_present('ejson-keys', ejson: false)
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
      %r{The following resources were pruned:.*secret( "|\/)catphotoscom},
      %r{The following resources were pruned:.*secret( "|\/)monitoring-token},
      %r{The following resources were pruned:.*secret( "|\/)unused-secret},
    ])

    ejson_cloud.refute_resource_exists('secret', 'unused-secret')
    ejson_cloud.refute_resource_exists('secret', 'catphotoscom')
    ejson_cloud.refute_resource_exists('secret', 'monitoring-token')

    # Check ejson-keys is not deleted
    ejson_cloud.assert_secret_present('ejson-keys')
  end

  def test_can_deploy_template_dir_with_only_secrets_ejson
    ejson_cloud = FixtureSetAssertions::EjsonCloud.new(@namespace)
    ejson_cloud.create_ejson_keys_secret
    assert_deploy_success(deploy_fixtures("ejson-cloud", subset: ["secrets.ejson"]))
    assert_logs_match_all([
      "Result: SUCCESS",
      %r{Secret\/catphotoscom\s+Available},
      %r{Secret\/monitoring-token\s+Available},
      %r{Secret\/unused-secret\s+Available},
    ], in_order: true)
  end

  def test_ejson_works_with_label_selectors
    value = "master"
    selector = KubernetesDeploy::LabelSelector.parse("branch=#{value}")
    ejson_cloud = FixtureSetAssertions::EjsonCloud.new(@namespace)
    ejson_cloud.create_ejson_keys_secret
    assert_deploy_success(deploy_fixtures("ejson-cloud", subset: ["secrets.ejson"], selector: selector))
    assert_logs_match_all([
      "Result: SUCCESS",
      %r{Secret\/catphotoscom\s+Available},
      %r{Secret\/monitoring-token\s+Available},
      %r{Secret\/unused-secret\s+Available},
    ], in_order: true)
    secret = kubeclient.get_secret('catphotoscom', @namespace)
    assert_equal(value, secret.metadata.labels.to_h[:branch])
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
    assert_logs_match_all([
      "Result: FAILURE",
      "Namespace this-certainly-should-not-exist not found",
    ], in_order: true)
  ensure
    @namespace = original_ns
  end

  def test_unmanaged_pod_failure_halts_deploy_and_displays_logs_correctly
    result = deploy_fixtures(
      "hello-cloud",
      subset: ["configmap-data.yml", "unmanaged-pod-1.yml.erb", "unmanaged-pod-2.yml.erb", "web.yml.erb"]
    ) do |fixtures|
      pod = fixtures["unmanaged-pod-1.yml.erb"]["Pod"].first
      container = pod["spec"]["containers"].first
      container["command"] = ["sh", "-c", "/some/bad/path"] # should throw an error
    end
    assert_deploy_failure(result)

    assert_logs_match_all([
      "Logs from Pod/unmanaged-pod-2",
      "Hello from the second command runner!", # logs from successful pod printed before summary
      "Result: FAILURE",
      "Failed to deploy 1 priority resource",
      %r{Pod\/unmanaged-pod-1-\w+-\w+: FAILED},
      "Logs from container 'hello-cloud'",
      "sh: /some/bad/path: not found", # logs from failed pod printed in summary
    ], in_order: true)
    refute_logs_match(%r{some/bad/path.*Result\: FAILURE}m) # failed pod logs not also displayed before summary

    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_unmanaged_pod_statuses("Failed", 1)
    hello_cloud.assert_unmanaged_pod_statuses("Succeeded", 1)
    hello_cloud.assert_configmap_data_present # priority resource
    hello_cloud.refute_web_resources_exist
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
      %r{Deployment/web\s+1 replica, 1 updatedReplica, 1 availableReplica},
      %r{Service/web\s+Selects at least 1 pod},
      %r{Deployment/web\s+0 replicas},
      %r{Service/web\s+Doesn't require any endpoint},
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

  def test_can_deploy_statefulset_with_zero_replicas
    result = deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "stateful_set.yml"]) do |fixtures|
      stateful = fixtures["stateful_set.yml"]["StatefulSet"].first
      stateful["spec"]["replicas"] = 0
    end
    assert_deploy_success(result)

    pods = kubeclient.get_pods(namespace: @namespace)
    assert_equal(0, pods.length, "Pods were running from zero-replica deployment")

    assert_logs_match_all([
      %r{Service/stateful-busybox\s+Doesn't require any endpoint},
      %r{StatefulSet/stateful-busybox\s+0 replicas},
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

  def test_deploy_successful_with_multiple_template_paths
    result = deploy_dirs(fixture_path("test-partials"), fixture_path("cronjobs"),
      bindings: { 'supports_partials' => 'yep' })
    assert_deploy_success(result)

    assert_logs_match_all([
      %r{ConfigMap/config-for-pod1\s+Available},
      %r{ConfigMap/config-for-pod2\s+Available},
      %r{ConfigMap/independent-configmap\s+Available},
      %r{CronJob/my-cronjob\s+Exists},
      %r{Deployment/web\s+1 replica, 1 updatedReplica, 1 availableReplica},
      %r{Pod/pod1\s+Succeeded},
      %r{Pod/pod2\s+Succeeded},
    ])
  end

  def test_deploy_successful_with_multiple_template_paths_multiple_partials
    result = deploy_dirs(fixture_path("test-partials"), fixture_path("test-partials2"),
      bindings: { 'supports_partials' => 'yep' })
    assert_deploy_success(result)

    assert_logs_match_all([
      %r{ConfigMap/config-for-pod1\s+Available},
      %r{ConfigMap/config-for-pod2\s+Available},
      %r{ConfigMap/independent-configmap\s+Available},
      %r{Deployment/web\s+1 replica, 1 updatedReplica, 1 availableReplica},
      %r{Deployment/web-from-partial\s+1 replica, 1 updatedReplica, 1 availableReplica},
      %r{Pod/pod1\s+Succeeded},
      %r{Pod/pod2\s+Succeeded},
    ])
  end

  def test_deploy_successful_partials_with_filename_args
    partial_file_1 = File.join(fixture_path("test-partials"), "deployment.yaml.erb")
    partial_file_2 = File.join(fixture_path("test-partials2"), "deployment.yml.erb")
    result = deploy_dirs(partial_file_1, partial_file_2, bindings: { 'supports_partials' => 'yep' })
    assert_deploy_success(result)

    assert_logs_match_all([
      %r{ConfigMap/config-for-pod1\s+Available},
      %r{ConfigMap/config-for-pod2\s+Available},
      %r{ConfigMap/independent-configmap\s+Available},
      %r{Deployment/web\s+1 replica, 1 updatedReplica, 1 availableReplica},
      %r{Deployment/web-from-partial\s+1 replica, 1 updatedReplica, 1 availableReplica},
      %r{Pod/pod1\s+Succeeded},
      %r{Pod/pod2\s+Succeeded},
    ])
  end

  def test_ejson_secrets_are_created_from_multiple_template_paths
    ejson_cloud = FixtureSetAssertions::EjsonCloud.new(@namespace)
    ejson_cloud.create_ejson_keys_secret

    result = deploy_dirs(fixture_path("ejson-cloud"), fixture_path("ejson-cloud2"))
    assert_deploy_success(result)

    assert_logs_match_all([
      %r{Deployment/web\s+1 replica, 1 updatedReplica, 1 availableReplica},
      %r{Secret/a-secret\s+Available},
      %r{Secret/catphotoscom\s+Available},
      %r{Secret/monitoring-token\s+Available},
      %r{Secret/unused-secret\s+Available},
    ])
  end

  def test_deploy_successful_with_filename_arg
    result = deploy_dirs(File.join(fixture_path("hello-cloud"), "service-account.yml"))
    assert_deploy_success(result)
    assert_logs_match_all([
      "Successfully deployed 1 resource",
      %r{ServiceAccount/build-robot(\s+)Created},
    ], in_order: true)
  end

  def test_deploy_successful_with_both_filename_and_template_dir
    filepath = File.join(fixture_path("hello-cloud"), "service-account.yml")
    result = deploy_dirs(filepath, fixture_path("cronjobs"))
    assert_deploy_success(result)
    assert_logs_match_all([
      "Successfully deployed 2 resources",
      %r{CronJob/my-cronjob(\s+)Exists},
      %r{ServiceAccount/build-robot(\s+)Created},
    ], in_order: true)
  end

  def test_deploy_successful_multiple_filenames_different_directories
    hello_cloud_file = File.join(fixture_path("hello-cloud"), "service-account.yml")
    cronjob_file = File.join(fixture_path("cronjobs"), "cronjob.yaml.erb")
    result = deploy_dirs(hello_cloud_file, cronjob_file)
    assert_deploy_success(result)
    assert_logs_match_all([
      "Successfully deployed 2 resources",
      %r{CronJob/my-cronjob(\s+)Exists},
      %r{ServiceAccount/build-robot(\s+)Created},
    ], in_order: true)
  end

  def test_deploy_successful_with_filename_arg_requiring_ejson
    ejson_cloud = FixtureSetAssertions::EjsonCloud.new(@namespace)
    ejson_cloud.create_ejson_keys_secret

    ejson_path = fixture_path("ejson-cloud")
    secrets_file = File.join(ejson_path, "secrets.ejson")
    web_file = File.join(ejson_path, "web.yaml")

    result = deploy_dirs(secrets_file, web_file)
    assert_deploy_success(result)
    assert_logs_match_all([
      %r{Deployment/web\s+1 replica, 1 updatedReplica, 1 availableReplica},
      %r{Secret/catphotoscom\s+Available},
      %r{Secret/monitoring-token\s+Available},
      %r{Secret/unused-secret\s+Available},
    ])
  end

  def test_only_explicitly_listed_ejson_secrets_deployed_when_specifying_filename_args
    ejson_cloud = FixtureSetAssertions::EjsonCloud.new(@namespace)
    ejson_cloud.create_ejson_keys_secret

    web_file = File.join(fixture_path("ejson-cloud2"), "web.yml")
    ejson_dir = fixture_path("ejson-cloud")
    result = deploy_dirs(web_file, ejson_dir)
    assert_deploy_success(result)
    assert_logs_match_all([
      %r{Deployment/web\s+1 replica, 1 updatedReplica, 1 availableReplica},
      %r{Secret/catphotoscom\s+Available},
      %r{Secret/monitoring-token\s+Available},
      %r{Secret/unused-secret\s+Available},
    ])
    refute_logs_match(%r{Secret/a-secret\s+Available})
  end

  def test_deploy_aborts_immediately_if_metadata_name_missing
    result = deploy_fixtures("hello-cloud", subset: ["configmap-data.yml"]) do |fixtures|
      definition = fixtures["configmap-data.yml"]["ConfigMap"].first
      definition["metadata"].delete("name")
    end
    assert_deploy_failure(result)

    assert_logs_match_all([
      "Result: FAILURE",
      "Template is missing required field 'metadata.name'",
      "Template content:",
      "kind: ConfigMap",
      'metadata: {"labels"=>{"name"=>"hello-cloud-configmap-data", "app"=>"hello-cloud"}}',
    ], in_order: true)
  end

  def test_deploy_aborts_immediately_if_unmanged_pod_spec_missing
    result = deploy_fixtures("hello-cloud", subset: ["unmanaged-pod-1.yml.erb"]) do |fixtures|
      definition = fixtures["unmanaged-pod-1.yml.erb"]["Pod"].first
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
    result = deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "unmanaged-pod-1.yml.erb"]) do |fixtures|
      pod = fixtures["unmanaged-pod-1.yml.erb"]["Pod"].first
      pod["metadata"]["name"] = "oops-it-is-static"
    end
    assert_deploy_success(result)

    # Second deploy should fail because unmanaged pod already exists
    result = deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "unmanaged-pod-1.yml.erb"]) do |fixtures|
      pod = fixtures["unmanaged-pod-1.yml.erb"]["Pod"].first
      pod["metadata"]["name"] = "oops-it-is-static"
    end
    assert_deploy_failure(result)
    assert_logs_match("Unmanaged pods like Pod/oops-it-is-static must have unique names on every deploy")
  end

  def test_streams_unmanaged_pod_logs_when_only_one
    result = deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "unmanaged-pod-1.yml.erb"])
    assert_deploy_success(result)
    assert_logs_match(%r{Streaming logs from Pod/unmanaged-pod-1})

    reset_logger

    result = deploy_fixtures(
      "hello-cloud",
      subset: ["configmap-data.yml", "unmanaged-pod-1.yml.erb", "unmanaged-pod-2.yml.erb"]
    )
    assert_deploy_success(result)
    assert_logs_match_all([
      %r{Logs from Pod/unmanaged-pod-1},
      %r{Logs from Pod/unmanaged-pod-2},
    ])
    refute_logs_match(%r{Streaming logs from Pod/unmanaged-pod})
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
      "Successfully deployed 1 resource and failed to deploy 1 resource",
      "StatefulSet/stateful-busybox: FAILED",
      "app: Crashing repeatedly (exit 1). See logs for more information.",
      "Events (common success events excluded):",
      %r{\[Pod/stateful-busybox-\d\]\tBackOff: Back-off restarting failed container},
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
      "failed quota: resource-quotas", # from an event
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
    ejson_cloud.assert_secret_present('unused-secret', ejson: true)

    result = deploy_fixtures("ejson-cloud", prune: false) do |fixtures|
      fixtures["secrets.ejson"]["kubernetes_secrets"].delete("unused-secret")
    end
    assert_deploy_success(result)

    # The removed secret was not pruned
    ejson_cloud.assert_secret_present('unused-secret', ejson: true)
    # The remaining secrets also exist
    ejson_cloud.assert_secret_present('monitoring-token', ejson: true)
    ejson_cloud.assert_secret_present('catphotoscom', type: 'kubernetes.io/tls', ejson: true)
    ejson_cloud.assert_secret_present('ejson-keys', ejson: false)
  end

  def test_deploy_task_fails_when_ejson_keys_prunable
    ejson_cloud = FixtureSetAssertions::EjsonCloud.new(@namespace)
    ejson_cloud.create_ejson_keys_secret
    secret = kubeclient.get_secret('ejson-keys', @namespace)
    secret.metadata.annotations = {
      "kubectl.kubernetes.io/last-applied-configuration" => "test",
    }
    secret = kubeclient.update_secret(secret)
    assert(secret.metadata.annotations[KubernetesDeploy::KubernetesResource::LAST_APPLIED_ANNOTATION])

    assert_deploy_failure(deploy_fixtures("hello-cloud", subset: %w(role.yml)))
    ejson_cloud.assert_secret_present('ejson-keys')
    assert_logs_match_all([
      "Deploy cannot proceed because protected resource ",
      "Secret/#{KubernetesDeploy::EjsonSecretProvisioner::EJSON_KEYS_SECRET} would be pruned.",
      "Result: FAILURE",
      "Found kubectl.kubernetes.io/last-applied-configuration annotation on ejson-keys secret.",
      "kubernetes-deploy will not continue since it is extremely unlikely that this secret should be pruned.",
    ],
      in_order: true)
  end

  def test_deploy_task_succeeds_when_ejson_keys_prunable_but_prune_option_false
    ejson_cloud = FixtureSetAssertions::EjsonCloud.new(@namespace)
    ejson_cloud.create_ejson_keys_secret
    secret = kubeclient.get_secret('ejson-keys', @namespace)
    secret.metadata.annotations = {
      "kubectl.kubernetes.io/last-applied-configuration" => "test",
    }
    secret = kubeclient.update_secret(secret)
    assert(secret.metadata.annotations[KubernetesDeploy::KubernetesResource::LAST_APPLIED_ANNOTATION])

    assert_deploy_success(deploy_fixtures("hello-cloud", subset: %w(role.yml), prune: false))
    ejson_cloud.assert_secret_present('ejson-keys')
  end

  def test_deploy_task_succeeds_when_ejson_keys_not_present
    ejson_cloud = FixtureSetAssertions::EjsonCloud.new(@namespace)
    ejson_cloud.refute_resource_exists("secret", "ejson-keys")
    assert_deploy_success(deploy_fixtures("hello-cloud", subset: %w(role.yml)))
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
      %r{\[Job/hello-job\]\tDeadlineExceeded: Job was active longer than specified deadline \(\d+ events\)},
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
      "Template is missing required field 'kind'",
      "> Template content:",
      "apiVersion: v1",
      "kind: <missing>",
      'metadata: {"name"=>"test"}',
    ], in_order: true)
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

  def test_apply_failure_with_sensitive_resources_hides_raw_output
    logger.level = 0
    # An invalid PATCH produces the kind of error we want to catch, so first create a valid secret:
    assert_deploy_success(deploy_fixtures("hello-cloud", subset: %w(secret.yml)))
    # Then try to PATCH an immutable field
    result = deploy_fixtures("hello-cloud", subset: %w(secret.yml)) do |fixtures|
      secret = fixtures["secret.yml"]["Secret"].first
      secret["type"] = "something/invalid"
    end
    assert_deploy_failure(result)
    refute_logs_match(%r{Kubectl err:.*something/invalid})
    if server_dry_run_available?
      assert_logs_match_all([
        "Template validation failed",
        'Invalid template: Secret-hello-secret',
        /Detailed.* is unavailable as .* may contain sensitive data./,
      ])
    else
      assert_logs_match_all([
        "Command failed: apply -f",
        /WARNING:.*The raw output may be sensitive and so cannot be displayed/,
      ])
    end
  end

  def test_validation_failure_on_sensitive_resources_does_not_print_template
    selector = KubernetesDeploy::LabelSelector.parse("branch=master")
    assert_deploy_failure(deploy_fixtures("hello-cloud", subset: %w(secret.yml), selector: selector))
    assert_logs_match_all([
      "Template validation failed",
      "Invalid template: Secret-hello-secret",
      "selector branch=master passed in, but no labels were defined",
    ], in_order: true)
    refute_logs_match("password")
    refute_logs_match("YWRtaW4=")
  end

  def test_render_failure_on_sensitive_resource_does_not_print_template
    assert_deploy_failure(deploy_fixtures("invalid-resources", subset: %w(bad_binding_secret.yml.erb)))
    assert_logs_match_all([
      "Failed to render and parse template",
      "Invalid template: bad_binding_secret.yml.erb",
      "undefined local variable or method",
      "Template content: Suppressed because it may contain a Secret",
    ], in_order: true)
    refute_logs_match("password")
    refute_logs_match("YWRtaW4=")
  end

  def test_missing_name_on_secret_does_not_print_template_at_all
    result = deploy_fixtures("hello-cloud", subset: %w(secret.yml)) do |fixtures|
      secret = fixtures["secret.yml"]["Secret"].first
      secret["metadata"].delete("name")
    end
    assert_deploy_failure(result)

    assert_logs_match_all([
      "Invalid template: secret.yml",
      "Template is missing required field 'metadata.name'",
      "Template content: Suppressed because it may contain a Secret",
    ], in_order: true)

    refute_logs_match("apiVersion:")
    refute_logs_match("password")
    refute_logs_match("YWRtaW4=")
  end

  def test_missing_name_on_unknown_resource_prints_metadata_but_not_body
    result = deploy_fixtures("hello-cloud", subset: %w(secret.yml)) do |fixtures|
      secret = fixtures["secret.yml"]["Secret"].first
      secret["metadata"].delete("name")
      secret["kind"] = "SpecialSecret"
      secret["metadata"]["labels"] = { "should_appear" => true }
    end
    assert_deploy_failure(result)

    assert_logs_match_all([
      "Invalid template: secret.yml",
      "Template is missing required field 'metadata.name'",
      "apiVersion: v1",
      "kind: SpecialSecret",
      'metadata: {"labels"=>{"should_appear"=>true}}',
      "<Template body suppressed because content sensitivity could not be determined.>",
    ], in_order: true)

    refute_logs_match("password")
    refute_logs_match("YWRtaW4=")
  end

  # Note: These tests assume a default storage class with a dynamic provisioner and 'Immediate' bind
  def test_pvc
    pvname = "local0001"
    storage_class_name = "k8s-deploy-test"

    assert_deploy_success(deploy_fixtures("pvc", subset: ["wait_for_first_consumer_storage_class.yml"]))

    TestProvisioner.prepare_pv(pvname, storage_class_name: storage_class_name)
    assert_deploy_success(deploy_fixtures("pvc"))

    assert_logs_match_all([
      "Successfully deployed 4 resource",
      "Successful resources",
      %r{PersistentVolumeClaim/with-storage-class\s+Bound},
      %r{PersistentVolumeClaim/without-storage-class\s+Bound},
      %r{Pod/pvc\s+Succeeded},
      %r{StorageClass/k8s-deploy-test\s+Exists},
    ], in_order: true)

  ensure
    kubeclient.delete_persistent_volume(pvname)
    storage_v1_kubeclient.delete_storage_class(storage_class_name)
  end

  def test_pvc_no_bind
    pvname = "local0002"
    storage_class_name = "k8s-deploy-test-no-bind"

    result = deploy_fixtures("pvc", subset: ["wait_for_first_consumer_storage_class.yml"]) do |fixtures|
      sc = fixtures["wait_for_first_consumer_storage_class.yml"]["StorageClass"].first
      sc["metadata"]["name"] = storage_class_name
    end
    assert_deploy_success(result)

    TestProvisioner.prepare_pv(pvname, storage_class_name: storage_class_name)
    result = deploy_fixtures("pvc", subset: ["pvc.yml"]) do |fixtures|
      pvc = fixtures["pvc.yml"]["PersistentVolumeClaim"].first
      pvc["spec"]["storageClassName"] = storage_class_name
    end
    assert_deploy_success(result)

    assert_logs_match_all([
      "Successfully deployed 2 resource",
      "Successful resources",
      %r{PersistentVolumeClaim/with-storage-class\s+Pending},
      %r{PersistentVolumeClaim/without-storage-class\s+Bound},
    ], in_order: true)

  ensure
    kubeclient.delete_persistent_volume(pvname)
    storage_v1_kubeclient.delete_storage_class(storage_class_name)
  end

  def test_pvc_immediate_bind
    pvname = "local0003"
    storage_class_name = "k8s-deploy-test-immediate-bind"

    result = deploy_fixtures("pvc", subset: ["wait_for_first_consumer_storage_class.yml"]) do |fixtures|
      sc = fixtures["wait_for_first_consumer_storage_class.yml"]["StorageClass"].first
      sc["metadata"]["name"] = storage_class_name
      sc["volumeBindingMode"] = "Immediate"
    end
    assert_deploy_success(result)

    TestProvisioner.prepare_pv(pvname, storage_class_name: storage_class_name)
    result = deploy_fixtures("pvc", subset: ["pvc.yml"]) do |fixtures|
      pvc = fixtures["pvc.yml"]["PersistentVolumeClaim"].first
      pvc["spec"]["storageClassName"] = storage_class_name
    end
    assert_deploy_success(result)

    assert_logs_match_all([
      "Successfully deployed 2 resource",
      "Successful resources",
      %r{PersistentVolumeClaim/with-storage-class\s+Bound},
      %r{PersistentVolumeClaim/without-storage-class\s+Bound},
    ], in_order: true)

  ensure
    kubeclient.delete_persistent_volume(pvname)
    storage_v1_kubeclient.delete_storage_class(storage_class_name)
  end

  def test_pvc_no_pv
    storage_class_name = "k8s-deploy-test-no-pv"

    result = deploy_fixtures("pvc", subset: ["wait_for_first_consumer_storage_class.yml"]) do |fixtures|
      sc = fixtures["wait_for_first_consumer_storage_class.yml"]["StorageClass"].first
      sc["metadata"]["name"] = storage_class_name
    end
    assert_deploy_success(result)

    result = deploy_fixtures("pvc", subset: ["pvc.yml", "pod.yml"]) do |fixtures|
      pvc = fixtures["pvc.yml"]["PersistentVolumeClaim"].first
      pvc["spec"]["storageClassName"] = storage_class_name
    end
    assert_deploy_failure(result)

    assert_logs_match_all([
      "Failed to deploy 1 priority resource",
      "Pod/pvc: TIMED OUT (timeout: 10s)",
      %r{Pod could not be scheduled because 0/\d+ nodes are available:},
      /\d+ node[(]s[)] didn't find available persistent volumes to bind./,
    ], in_order: true)

  ensure
    storage_v1_kubeclient.delete_storage_class(storage_class_name)
  end

  def test_pvc_no_pv_or_sc
    storage_class_name = "k8s-deploy-test-no-pv-or-sc"

    result = deploy_fixtures("pvc", subset: ["pvc.yml", "pod.yml"]) do |fixtures|
      pvc = fixtures["pvc.yml"]["PersistentVolumeClaim"].first
      pvc["spec"]["storageClassName"] = storage_class_name
    end
    assert_deploy_failure(result)

    assert_logs_match_all([
      "Failed to deploy 1 priority resource",
      "PersistentVolumeClaim/with-storage-class: TIMED OUT (timeout: 10s)",
      "PVC specified a StorageClass of #{storage_class_name} but the resource does not exist",
    ], in_order: true)
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
