# frozen_string_literal: true
require 'integration_test_helper'

class SerialDeployTest < Krane::IntegrationTest
  include StatsD::Instrument::Assertions
  ## GLOBAL CONTEXT MANIPULATION TESTS
  # This can be run in parallel if we allow passing the config file path to DeployTask.new
  # See https://github.com/Shopify/krane/pull/428#pullrequestreview-209720675

  FIXTURE_CONTEXT = 'minikube'

  def test_unreachable_context
    old_config = ENV['KUBECONFIG']
    begin
      ENV['KUBECONFIG'] = File.join(__dir__, '../fixtures/kube-config/dummy_config.yml')
      kubectl_instance = build_kubectl(timeout: '0.1s')
      result = deploy_fixtures('hello-cloud', kubectl_instance: kubectl_instance, context: FIXTURE_CONTEXT)
      assert_deploy_failure(result)
      assert_logs_match_all([
        'Result: FAILURE',
        "Something went wrong connecting to #{FIXTURE_CONTEXT}", # minikube context is hardcoded in fixtures
      ], in_order: true)
    ensure
      ENV['KUBECONFIG'] = old_config
    end
  end

  def test_multiple_configuration_files
    old_config = ENV['KUBECONFIG']
    config_file = File.join(__dir__, '../fixtures/kube-config/unknown_config.yml')
    ENV['KUBECONFIG'] = config_file
    result = deploy_fixtures('hello-cloud')
    assert_deploy_failure(result)
    assert_logs_match_all([
      'Result: FAILURE',
      'Configuration invalid',
      "Kubeconfig not found at #{config_file}",
    ], in_order: true)
    reset_logger

    ENV['KUBECONFIG'] = " : "
    result = deploy_fixtures('hello-cloud')
    assert_deploy_failure(result)
    assert_logs_match_all([
      'Result: FAILURE',
      'Configuration invalid',
      "Kubeconfig file name(s) not set in $KUBECONFIG",
    ], in_order: true)
    reset_logger

    default_config = "#{Dir.home}/.kube/config"
    extra_config = File.join(__dir__, '../fixtures/kube-config/dummy_config.yml')
    ENV['KUBECONFIG'] = "#{default_config}:#{extra_config}"
    result = deploy_fixtures('hello-cloud', subset: ["configmap-data.yml"])
    assert_deploy_success(result)
  ensure
    ENV['KUBECONFIG'] = old_config
  end

  # We want to be sure that failures to apply resources with potentially sensitive output don't leak any content.
  # Currently our only sensitive resource is `Secret`, but we cannot reproduce a failure scenario where the kubectl
  # output contains the filename (which would trigger some extra logging). This test stubs `Deployment` to be sensitive
  # to recreate such a condition
  def test_apply_failure_with_sensitive_resources_hides_template_content
    logger.level = 0
    Krane::Apps::Deployment.any_instance.expects(:sensitive_template_content?).returns(true).at_least_once
    result = deploy_fixtures("hello-cloud", subset: ["web.yml.erb"], render_erb: true) do |fixtures|
      bad_port_name = "http_test_is_really_long_and_invalid_chars"
      svc = fixtures["web.yml.erb"]["Service"].first
      svc["spec"]["ports"].first["targetPort"] = bad_port_name
      deployment = fixtures["web.yml.erb"]["Deployment"].first
      deployment["spec"]["template"]["spec"]["containers"].first["ports"].first["name"] = bad_port_name
    end
    assert_deploy_failure(result)
    refute_logs_match(%r{Kubectl err:.*something/invalid})

    assert_logs_match_all([
      "Command failed: apply -f",
      /Invalid template: Deployment.apps-web.*\.yml/,
    ])

    refute_logs_match("kind: Deployment") # content of the sensitive template
  end

  ## METRICS TESTS
  # Metrics tests must be run serially to ensure our global client isn't capturing metrics from other tests
  def test_stage_related_metrics_include_custom_tags_from_namespace
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    kubeclient.patch_namespace(hello_cloud.namespace, metadata: { labels: { foo: 'bar' } })
    metrics = capture_statsd_calls(client: Krane::StatsD.client) do
      assert_deploy_success(deploy_fixtures("hello-cloud", subset: ["configmap-data.yml"], wait: false))
    end

    %w(
      Krane.validate_configuration.duration
      Krane.discover_resources.duration
      Krane.discover_resources.count
      Krane.validate_resources.duration
      Krane.initial_status.duration
      Krane.priority_resources.duration
      Krane.priority_resources.count
      Krane.apply_all.duration
      Krane.normal_resources.duration
      Krane.all_resources.duration

    ).each do |expected_metric|
      metric = metrics.find { |m| m.name == expected_metric }
      refute_nil(metric, "Metric #{expected_metric} not emitted")
      assert_includes(metric.tags, "foo:bar", "Metric #{expected_metric} did not have custom tags")
    end
  end

  def test_all_expected_statsd_metrics_emitted_with_essential_tags
    metrics = capture_statsd_calls(client: Krane::StatsD.client) do
      result = deploy_fixtures('hello-cloud', subset: ['configmap-data.yml'], wait: false, sha: 'test-sha')
      assert_deploy_success(result)
    end

    assert_equal(1, metrics.count { |m| m.type == :_e }, "Expected to find one event metric")

    %w(
      Krane.validate_configuration.duration
      Krane.discover_resources.duration
      Krane.discover_resources.count
      Krane.initial_status.duration
      Krane.validate_resources.duration
      Krane.priority_resources.duration
      Krane.priority_resources.count
      Krane.apply_all.duration
      Krane.normal_resources.duration
      Krane.sync.duration
      Krane.all_resources.duration
    ).each do |expected_metric|
      metric = metrics.find { |m| m.name == expected_metric }
      refute_nil(metric, "Metric #{expected_metric} not emitted")
      assert_includes(metric.tags, "namespace:#{@namespace}", "#{metric.name} is missing namespace tag")
      assert_includes(metric.tags, "context:#{KubeclientHelper::TEST_CONTEXT}", "#{metric.name} is missing context tag")
      assert_includes(metric.tags, "sha:test-sha", "#{metric.name} is missing sha tag")
    end
  end

  def test_global_deploy_emits_expected_statsd_metrics
    metrics = capture_statsd_calls(client: Krane::StatsD.client) do
      assert_deploy_success(deploy_global_fixtures('globals'))
    end

    assert_equal(1, metrics.count { |m| m.type == :_e }, "Expected to find one event metric")

    %w(
      Krane.validate_configuration.duration
      Krane.discover_resources.duration
      Krane.discover_resources.count
      Krane.initial_status.duration
      Krane.validate_resources.duration
      Krane.apply_all.duration
      Krane.normal_resources.duration
      Krane.sync.duration
      Krane.all_resources.duration
    ).each do |expected_metric|
      metric = metrics.find { |m| m.name == expected_metric }
      refute_nil(metric, "Metric #{expected_metric} not emitted")
      assert_includes(metric.tags, "context:#{KubeclientHelper::TEST_CONTEXT}", "#{metric.name} is missing context tag")
    end
  end

  ## BLACK BOX TESTS
  # test_global_deploy_black_box_failure is in test/integration/krane_test.rb
  # because it does not modify global state. The following two tests modify
  # global state and must be run in serially
  def test_global_deploy_black_box_success
    setup_template_dir("globals") do |target_dir|
      flags = "-f #{target_dir} --selector app=krane"
      out, err, status = krane_black_box("global-deploy", "#{KubeclientHelper::TEST_CONTEXT} #{flags}")
      assert_empty(out)
      assert_match("Success", err)
      assert_predicate(status, :success?)
    end
  ensure
    build_kubectl.run("delete", "-f", fixture_path("globals"), use_namespace: false, log_failure: false)
  end

  def test_global_deploy_black_box_timeout
    setup_template_dir("globals") do |target_dir|
      flags = "-f #{target_dir} --selector app=krane --global-timeout=0.1s"
      out, err, status = krane_black_box("global-deploy", "#{KubeclientHelper::TEST_CONTEXT} #{flags}")
      assert_empty(out)
      assert_match("TIMED OUT", err)
      refute_predicate(status, :success?)
      assert_equal(status.exitstatus, 70)
    end
  ensure
    build_kubectl.run("delete", "-f", fixture_path("globals"), use_namespace: false, log_failure: false)
  end

  def test_global_deploy_prune_black_box_success
    namespace_name = "test-app"
    setup_template_dir("globals") do |target_dir|
      flags = "-f #{target_dir} --selector app=krane"
      namespace_str = "apiVersion: v1\nkind: Namespace\nmetadata:\n  name: #{namespace_name}"\
      "\n  labels:\n    app: krane"
      File.write(File.join(target_dir, "namespace.yml"), namespace_str)
      out, err, status = krane_black_box("global-deploy", "#{KubeclientHelper::TEST_CONTEXT} #{flags}")
      assert_empty(out)
      assert_match("Successfully deployed 3 resource", err)
      assert_match(/#{namespace_name}\W+Exists/, err)
      assert_match("Success", err)
      assert_predicate(status, :success?)

      flags = "-f #{target_dir}/storage_classes.yml --selector app=krane"
      out, err, status = krane_black_box("global-deploy", "#{KubeclientHelper::TEST_CONTEXT} #{flags}")
      assert_empty(out)
      refute_match(namespace_name, err) # Asserting that the namespace is not pruned
      assert_match("Pruned 1 resource and successfully deployed 1 resource", err)
      assert_predicate(status, :success?)
    end
  ensure
    build_kubectl.run("delete", "-f", fixture_path("globals"), use_namespace: false, log_failure: false)
    build_kubectl.run("delete", "namespace", namespace_name, use_namespace: false, log_failure: false)
  end

  ## TESTS THAT DEPLOY CRDS
  # Tests that create CRDs cannot be run in parallel with tests that deploy namespaced resources
  # This is because the CRD kind may torn down in the middle of the namespaced deploy, causing it to be seen
  # when we build the pruning whitelist, but gone by the time we attempt to list instances for pruning purposes.
  # When this happens, the namespaced deploy will fail with an `apply` error.
  def test_cr_merging
    assert_deploy_success(deploy_global_fixtures("crd", subset: %(mail.yml)))
    result = deploy_fixtures("crd", subset: %w(mail_cr.yml)) do |f|
      cr = f.dig("mail_cr.yml", "Mail").first
      cr["kind"] = add_unique_prefix_for_test(cr["kind"])
    end
    assert_deploy_success(result)

    result = deploy_fixtures("crd", subset: %w(mail_cr.yml)) do |f|
      cr = f.dig("mail_cr.yml", "Mail").first
      cr["spec"]["something"] = 5
      cr["kind"] = add_unique_prefix_for_test(cr["kind"])
    end
    assert_deploy_success(result)
  end

  def test_custom_resources_predeployed
    assert_deploy_success(deploy_global_fixtures("crd", subset: %w(mail.yml things.yml widgets.yml)) do |f|
      mail = f.dig("mail.yml", "CustomResourceDefinition").first
      mail["metadata"]["annotations"] = {}

      things = f.dig("things.yml", "CustomResourceDefinition").first
      things["metadata"]["annotations"] = {
        "krane.shopify.io/predeployed" => "true",
      }

      widgets = f.dig("widgets.yml", "CustomResourceDefinition").first
      widgets["metadata"]["annotations"] = {
        "krane.shopify.io/predeployed" => "false",
      }
    end)
    reset_logger

    result = deploy_fixtures("crd", subset: %w(mail_cr.yml things_cr.yml widgets_cr.yml)) do |f|
      f.each do |_filename, contents|
        contents.each do |_kind, crs| # all of the resources are CRs, so change all of them
          crs.each { |cr| cr["kind"] = add_unique_prefix_for_test(cr["kind"]) }
        end
      end
    end
    assert_deploy_success(result)

    mail_cr_id = "#{add_unique_prefix_for_test('Mail')}/my-first-mail"
    thing_cr_id = "#{add_unique_prefix_for_test('Thing')}/my-first-thing"
    widget_cr_id = "#{add_unique_prefix_for_test('Widget')}/my-first-widget"
    assert_logs_match_all([
      /Phase 3: Predeploying priority resources/,
      /Successfully deployed in \d.\ds: #{mail_cr_id}/,
      /Successfully deployed in \d.\ds: #{thing_cr_id}/,
      /Phase 4: Deploying all resources/,
      /Successfully deployed in \d.\ds: #{mail_cr_id}, #{thing_cr_id}, #{widget_cr_id}/,
    ], in_order: true)
    refute_logs_match(
      /Successfully deployed in \d.\ds: #{widget_cr_id}/,
    )
  end

  def test_cr_deploys_without_rollout_conditions_when_none_present
    assert_deploy_success(deploy_global_fixtures("crd", subset: %(widgets.yml)))
    result = deploy_fixtures("crd", subset: %w(widgets_cr.yml)) do |f|
      f.each do |_filename, contents| # all of the resources are CRs, so change all of them
        contents.each do |_kind, crs|
          crs.each { |cr| cr["kind"] = add_unique_prefix_for_test(cr["kind"]) }
        end
      end
    end

    assert_deploy_success(result)
    prefixed_kind = add_unique_prefix_for_test("Widget")
    assert_logs_match_all([
      "Don't know how to monitor resources of type #{prefixed_kind}.",
      "Assuming #{prefixed_kind}/my-first-widget deployed successfully.",
      %r{Widget/my-first-widget\s+Exists},
    ])
  end

  def test_cr_success_with_default_rollout_conditions
    assert_deploy_success(deploy_global_fixtures("crd", subset: %(with_default_conditions.yml)))
    success_conditions = {
      "status" => {
        "observedGeneration" => 1,
        "conditions" => [
          {
            "type" => "Ready",
            "reason" => "test",
            "message" => "test",
            "status" => "True",
          },
        ],
      },
    }

    result = deploy_fixtures("crd", subset: ["with_default_conditions_cr.yml"]) do |resource|
      cr = resource["with_default_conditions_cr.yml"]["Parameterized"].first
      cr.merge!(success_conditions)
      cr["kind"] = add_unique_prefix_for_test(cr["kind"])
    end
    assert_deploy_success(result)
    assert_logs_match_all([
      %r{Successfully deployed in .*: #{add_unique_prefix_for_test("Parameterized")}\/with-default-params},
      %r{Parameterized/with-default-params\s+Healthy},
    ])
  end

  def test_priority_resource_timeout_status_should_be_timed_out
    assert_deploy_success(deploy_global_fixtures("crd", subset: %(with_default_conditions.yml)))
    result = deploy_fixtures("crd", subset: ["with_default_conditions_cr.yml"]) do |resource|
      cr = resource["with_default_conditions_cr.yml"]["Parameterized"].first
      cr["kind"] = add_unique_prefix_for_test(cr["kind"])
      cr["metadata"]["annotations"] = { "krane.shopify.io/timeout-override" => "0.1s" }
    end
    assert_deploy_failure(result, :timed_out)
  end

  def test_cr_success_with_service
    filepath = "#{fixture_path('crd')}/service_cr.yml"
    out, err, st = build_kubectl.run("create", "-f", filepath, log_failure: true, use_namespace: false)
    assert(st.success?, "Failed to create CRD: #{out}\n#{err}")

    assert_deploy_success(deploy_fixtures("crd", subset: %w(web.yml)))

    refute_logs_match(/Predeploying priority resources/)
    assert_logs_match_all([/Phase 3: Deploying all resources/])
  ensure
    build_kubectl.run("delete", "-f", filepath, use_namespace: false, log_failure: false)
  end

  def test_cr_failure_with_default_rollout_conditions
    assert_deploy_success(deploy_global_fixtures("crd", subset: %(with_default_conditions.yml)))
    failure_conditions = {
      "status" => {
        "observedGeneration" => 1,
        "conditions" => [
          {
            "type" => "Failed",
            "reason" => "test",
            "message" => "custom resource rollout failed",
            "status" => "True",
          },
        ],
      },
    }

    result = deploy_fixtures("crd", subset: ["with_default_conditions_cr.yml"]) do |resource|
      cr = resource["with_default_conditions_cr.yml"]["Parameterized"].first
      cr.merge!(failure_conditions)
      cr["kind"] = add_unique_prefix_for_test(cr["kind"])
    end
    assert_deploy_failure(result)

    assert_logs_match_all([
      "Parameterized/with-default-params: FAILED",
      "custom resource rollout failed",
      "Final status: Unhealthy",
    ], in_order: true)
  end

  def test_cr_success_with_arbitrary_rollout_conditions
    assert_deploy_success(deploy_global_fixtures("crd", subset: %(with_custom_conditions.yml)))

    success_conditions = {
      "spec" => {},
      "status" => {
        "observedGeneration" => 1,
        "test_field" => "success_value",
        "condition" => "success_value",
      },
    }

    result = deploy_fixtures("crd", subset: ["with_custom_conditions_cr.yml"]) do |resource|
      cr = resource["with_custom_conditions_cr.yml"]["Customized"].first
      cr["kind"] = add_unique_prefix_for_test(cr["kind"])
      cr.merge!(success_conditions)
    end
    assert_deploy_success(result)
    assert_logs_match_all([
      %r{Successfully deployed in .*: #{add_unique_prefix_for_test("Customized")}\/with-customized-params},
    ])
  end

  def test_cr_failure_with_arbitrary_rollout_conditions
    assert_deploy_success(deploy_global_fixtures("crd", subset: %(with_custom_conditions.yml)))
    cr = load_fixtures("crd", ["with_custom_conditions_cr.yml"])
    failure_conditions = {
      "spec" => {},
      "status" => {
        "test_field" => "failure_value",
        "error_msg" => "test error message jsonpath",
        "observedGeneration" => 1,
        "condition" => "failure_value",
      },
    }

    result = deploy_fixtures("crd", subset: ["with_custom_conditions_cr.yml"]) do |resource|
      cr = resource["with_custom_conditions_cr.yml"]["Customized"].first
      cr["kind"] = add_unique_prefix_for_test(cr["kind"])
      cr.merge!(failure_conditions)
    end
    assert_deploy_failure(result)
    assert_logs_match_all([
      "test error message jsonpath",
      "test custom error message",
    ])
  end

  def test_deploying_crs_with_invalid_crd_conditions_fails
    # Since CRDs are not always deployed along with their CRs and krane is not the only way CRDs are
    # deployed, we need to model the case where poorly configured rollout_conditions are present before deploying a CR
    fixtures = load_fixtures("crd", "with_custom_conditions.yml")
    crd = fixtures["with_custom_conditions.yml"]["CustomResourceDefinition"].first
    crd["metadata"]["annotations"].merge!(rollout_conditions_annotation_key => "blah")
    apply_scope_to_resources(fixtures, labels: "app=krane,test=#{@namespace}")
    Tempfile.open([@namespace, ".yml"]) do |f|
      f.write(YAML.dump(crd))
      f.fsync
      out, err, st = build_kubectl.run("create", "-f", f.path, log_failure: true, use_namespace: false)
      assert(st.success?, "Failed to create invalid CRD: #{out}\n#{err}")
    end

    result = deploy_fixtures("crd", subset: ["with_custom_conditions_cr.yml", "with_custom_conditions_cr2.yml"]) do |f|
      f.each do |_filename, contents|
        contents.each do |_kind, crs| # all of the resources are CRs, so change all of them
          crs.each { |cr| cr["kind"] = add_unique_prefix_for_test(cr["kind"]) }
        end
      end
    end
    assert_deploy_failure(result)
    prefixed_name = add_unique_prefix_for_test("Customized.stable.example.io-with-customized-params")
    assert_logs_match_all([
      /Invalid template: #{prefixed_name}/,
      /Rollout conditions are not valid JSON/,
      /Invalid template: #{prefixed_name}/,
      /Rollout conditions are not valid JSON/,
    ], in_order: true)
  end

  def test_crd_can_fail
    result = deploy_global_fixtures("crd", subset: %(mail.yml)) do |f|
      crd = f.dig("mail.yml", "CustomResourceDefinition").first
      names = crd.dig("spec", "names")
      names["listKind"] = 'Conflict'
    end
    assert_deploy_success(result)

    second_name = add_unique_prefix_for_test("others")
    result = deploy_global_fixtures("crd", subset: %(mail.yml), prune: false) do |f|
      crd = f.dig("mail.yml", "CustomResourceDefinition").first
      names = crd.dig("spec", "names")
      names["listKind"] = "Conflict"
      names["plural"] = second_name
      crd["metadata"]["name"] = "#{second_name}.stable.example.io"
    end
    assert_deploy_failure(result)
    assert_logs_match_all([
      "Deploying CustomResourceDefinition/#{second_name}.stable.example.io (timeout: 120s)",
      "CustomResourceDefinition/#{second_name}.stable.example.io: FAILED",
      'Final status: ListKindConflict ("Conflict" is already in use)',
    ])
  end

  def test_global_deploy_validation_catches_namespaced_cr
    assert_deploy_success(deploy_global_fixtures("crd", subset: %(mail.yml)))
    reset_logger
    result = deploy_global_fixtures("crd", subset: %(mail_cr.yml)) do |fixtures|
      mail = fixtures["mail_cr.yml"]["Mail"].first
      mail["kind"] = add_unique_prefix_for_test(mail["kind"])
    end
    assert_deploy_failure(result)
    assert_logs_match_all([
      "Phase 1: Initializing deploy",
      "Using resource selector app=krane",
      "All required parameters and files are present",
      "Discovering resources:",
      "- #{add_unique_prefix_for_test('Mail')}/#{add_unique_prefix_for_test('my-first-mail')}",
      "Result: FAILURE",
      "This command cannot deploy namespaced resources",
      "Namespaced resources:",
      "#{add_unique_prefix_for_test('my-first-mail')} (#{add_unique_prefix_for_test('Mail.stable.example.io')})",
    ])
  end

  def test_resource_discovery_stops_deploys_when_fetch_resources_kubectl_errs
    failure_msg = "Stubbed failure reason"
    Krane::ClusterResourceDiscovery.any_instance.expects(:fetch_resources).raises(Krane::FatalKubeAPIError, failure_msg)
    assert_deploy_failure(deploy_fixtures("hello-cloud", subset: ["configmap-data.yml"]))

    assert_logs_match_all([
      "Result: FAILURE",
      failure_msg,
    ], in_order: true)
  end

  def test_resource_discovery_stops_deploys_when_fetch_crds_kubectl_errs
    failure_msg = "Stubbed failure reason"
    Krane::ClusterResourceDiscovery.any_instance.expects(:crds).raises(Krane::FatalKubeAPIError, failure_msg)
    assert_deploy_failure(deploy_fixtures("hello-cloud", subset: ["configmap-data.yml"]))

    assert_logs_match_all([
      "Result: FAILURE",
      failure_msg,
    ], in_order: true)
  end

  def test_batch_dry_run_apply_failure_falls_back_to_individual_resource_dry_run_validation
    Krane::KubernetesResource.any_instance.expects(:validate_definition).with do |kwargs|
      kwargs[:kubectl].is_a?(Krane::Kubectl) && kwargs[:dry_run]
    end
    deploy_fixtures("hello-cloud", subset: %w(secret.yml)) do |fixtures|
      secret = fixtures["secret.yml"]["Secret"].first
      secret["bad_field"] = "bad_key"
    end
  end

  def test_batch_dry_run_apply_success_precludes_individual_resource_dry_run_validation
    Krane::KubernetesResource.any_instance.expects(:validate_definition).with { |params| params[:dry_run] == false }
    result = deploy_fixtures("hello-cloud", subset: %w(secret.yml))
    assert_deploy_success(result)
    assert_logs_match_all([
      "Result: SUCCESS",
      "Successfully deployed 1 resource",
    ], in_order: true)
  end

  # Note: After we drop support for K8s 1.21 this test can be removed, since webhooks must be dry-run safe.
  def test_resources_with_side_effect_inducing_webhooks_are_not_batched_server_side_dry_run
    result = deploy_global_fixtures("mutating_webhook_configurations", subset: %(ingress_hook.yaml))
    assert_deploy_success(result)

    # Note: We have to mock `has_side_effects?`, since this won't be possible with K8s 1.22+.
    Krane::AdmissionregistrationK8sIo::MutatingWebhookConfiguration::Webhook.any_instance.stubs(:has_side_effects?).returns(true)

    Krane::ResourceDeployer.any_instance.expects(:dry_run).with do |params|
      # We expect the ingress to not be included in the batch run
      params.length == 3 && (params.map(&:kind).sort == ["ConfigMap", "Deployment", "Service"])
    end.returns(true)

    [Krane::ConfigMap, Krane::Apps::Deployment, Krane::Service].each do |r|
      r.any_instance.expects(:validate_definition).with { |params| params[:dry_run] == false }
    end
    Krane::NetworkingK8sIo::Ingress.any_instance.expects(:validate_definition).with { |params| params[:dry_run] }
    result = deploy_fixtures('hello-cloud', subset: %w(web.yml.erb configmap-data.yml), render_erb: true)
    assert_deploy_success(result)
    assert_logs_match_all([
      "Result: SUCCESS",
      "Successfully deployed 4 resources",
    ], in_order: true)
  end

  # Note: After we drop support for K8s 1.21 this test can be removed, since webhooks must be dry-run safe.
  def test_resources_with_side_effect_inducing_webhooks_with_transitive_dependency_does_not_fail_batch_running
    result = deploy_global_fixtures("mutating_webhook_configurations", subset: %(secret_hook.yaml))
    assert_deploy_success(result)

    # Note: We have to mock `has_side_effects?`, since this won't be possible with K8s 1.22+.
    Krane::AdmissionregistrationK8sIo::MutatingWebhookConfiguration::Webhook.any_instance.stubs(:has_side_effects?).returns(true)

    actual_dry_runs = 0
    Krane::KubernetesResource.any_instance.expects(:validate_definition).with do |params|
      actual_dry_runs += 1 if params[:dry_run]
      true
    end.times(5)
    result = deploy_fixtures('hello-cloud', subset: %w(web.yml.erb secret.yml configmap-data.yml),
      render_erb: true) do |fixtures|
      container = fixtures['web.yml.erb']['Deployment'][0]['spec']['template']['spec']
      container['volumes'] = [{
        'name' => 'secret',
        'secret' => {
          'secretName' => fixtures['secret.yml']["Secret"][0]['metadata']['name'],
        },
      }]
    end
    assert_deploy_success(result)
    assert_equal(actual_dry_runs, 1)
    assert_logs_match_all([
      "Result: SUCCESS",
      "Successfully deployed 5 resources",
    ], in_order: true)
  end

  # Note: After we drop support for K8s 1.21 this test can be removed, since webhooks must be dry-run safe.
  def test_multiple_resources_with_side_effect_inducing_webhooks_are_properly_partitioned
    result = deploy_global_fixtures("mutating_webhook_configurations", subset: %(secret_hook.yaml ingress_hook.yaml))
    assert_deploy_success(result)

    # Note: We have to mock `has_side_effects?`, since this won't be possible with K8s 1.22+.
    Krane::AdmissionregistrationK8sIo::MutatingWebhookConfiguration::Webhook.any_instance.stubs(:has_side_effects?).returns(true)

    Krane::KubernetesResource.any_instance.expects(:validate_definition).with { |p| p[:dry_run] }.times(2)
    result = deploy_fixtures('hello-cloud', subset: %w(web.yml.erb secret.yml), render_erb: true) do |fixtures|
      fixtures["web.yml.erb"] = fixtures["web.yml.erb"].keep_if { |key| key == "Ingress" }
    end
    assert_deploy_success(result)
  end

  private

  def rollout_conditions_annotation_key
    Krane::Annotation.for(Krane::ApiextensionsK8sIo::CustomResourceDefinition::ROLLOUT_CONDITIONS_ANNOTATION)
  end

  def mutating_webhook_fixture(path)
    JSON.parse(File.read(path))['items'].map do |definition|
      Krane::AdmissionregistrationK8sIo::MutatingWebhookConfiguration.new(namespace: @namespace, context: @context, logger: @logger,
        definition: definition, statsd_tags: @namespace_tags)
    end
  end
end
