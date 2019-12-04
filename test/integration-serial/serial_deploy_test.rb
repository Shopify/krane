# frozen_string_literal: true
require 'integration_test_helper'

class SerialDeployTest < Krane::IntegrationTest
  include StatsD::Instrument::Assertions
  # This cannot be run in parallel because it either stubs a constant or operates in a non-exclusive namespace
  def test_deploying_to_protected_namespace_with_override_does_not_prune
    assert_deploy_success(deploy_fixtures("hello-cloud", subset: ['configmap-data.yml', 'disruption-budgets.yml'],
      protected_namespaces: [@namespace], prune: false))
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    hello_cloud.assert_configmap_data_present
    hello_cloud.assert_poddisruptionbudget
    assert_logs_match_all([
      /cannot be pruned/,
      /Please do not deploy to #{@namespace} unless you really know what you are doing/,
    ])

    result = deploy_fixtures("hello-cloud", subset: ["disruption-budgets.yml"],
      protected_namespaces: [@namespace], prune: false)
    assert_deploy_success(result)
    hello_cloud.assert_configmap_data_present # not pruned
    hello_cloud.assert_poddisruptionbudget
  end

  # This cannot be run in parallel because it needs to manipulate the global log level
  def test_create_secrets_from_ejson
    logger.level = ::Logger::DEBUG # for assertions that we don't log secret data

    # Create secrets
    ejson_cloud = FixtureSetAssertions::EjsonCloud.new(@namespace)
    ejson_cloud.create_ejson_keys_secret
    assert_deploy_success(deploy_fixtures("ejson-cloud"))
    ejson_cloud.assert_all_up
    assert_logs_match_all([
      %r{Secret\/catphotoscom\s+Available},
      %r{Secret\/unused-secret\s+Available},
      %r{Secret\/monitoring-token\s+Available},
    ])

    refute_logs_match(ejson_cloud.test_private_key)
    refute_logs_match(ejson_cloud.test_public_key)
    refute_logs_match(Base64.strict_encode64(ejson_cloud.catphotoscom_key_value))
  end

  def test_sensitive_output_suppressed_when_creating_secret_with_generate_name
    logger.level = ::Logger::DEBUG # for assertions that we don't log secret data

    # Create secrets
    result = deploy_fixtures("generateName", subset: "secret.yml")
    secret_name = /generate-name-secret-[a-z0-9]{5}/
    assert_deploy_success(result)
    assert_logs_match_all([
      'Deploying Secret/generate-name-secret-',
      'Successfully deployed 1 resource',
      %r{Secret/#{secret_name}\s+Available},
    ], in_order: true)

    refute_logs_match("cGFzc3dvcmQ=")
  end

  def test_sensitive_output_suppressed_when_creating_secret_with_generate_name_fails
    logger.level = ::Logger::DEBUG # for assertions that we don't log secret data

    # Create secrets
    result = deploy_fixtures("generateName", subset: "bad_secret.yml")
    assert_deploy_failure(result)
    assert_logs_match_all([
      'Failed to replace or create resource: secret/generate-name-secret-',
      "<suppressed sensitive output>",
    ], in_order: true)

    refute_logs_match("cGFzc3dvcmQ=")
  end

  # This can be run in parallel if we allow passing the config file path to DeployTask.new
  # See https://github.com/Shopify/krane/pull/428#pullrequestreview-209720675
  def test_unreachable_context
    old_config = ENV['KUBECONFIG']
    begin
      ENV['KUBECONFIG'] = File.join(__dir__, '../fixtures/kube-config/dummy_config.yml')
      kubectl_instance = build_kubectl(timeout: '0.1s')
      result = deploy_fixtures('hello-cloud', kubectl_instance: kubectl_instance)
      assert_deploy_failure(result)
      assert_logs_match_all([
        'Result: FAILURE',
        "Something went wrong connecting to #{TEST_CONTEXT}",
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

  def test_cr_merging
    assert_deploy_success(deploy_global_fixtures("crd", subset: %(mail.yml), clean_up: false))
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
  ensure
    wait_for_all_crd_deletion
  end

  def test_crd_can_fail
    result = deploy_global_fixtures("crd", subset: %(mail.yml), clean_up: false) do |f|
      crd = f.dig("mail.yml", "CustomResourceDefinition").first
      names = crd.dig("spec", "names")
      names["listKind"] = 'Conflict'
    end
    assert_deploy_success(result)

    result = deploy_global_fixtures("crd", subset: %(mail.yml), prune: false) do |f|
      crd = f.dig("mail.yml", "CustomResourceDefinition").first
      names = crd.dig("spec", "names")
      names["listKind"] = "Conflict"
      names["plural"] = "others"
      crd["metadata"]["name"] = "others.stable.example.io"
    end
    assert_deploy_failure(result)
    assert_logs_match_all([
      "Deploying CustomResourceDefinition/others.stable.example.io (timeout: 120s)",
      "CustomResourceDefinition/others.stable.example.io: FAILED",
      'Final status: ListKindConflict ("Conflict" is already in use)',
    ])
  ensure
    wait_for_all_crd_deletion
  end

  def test_custom_resources_predeployed_deprecated
    assert_deploy_success(deploy_global_fixtures("crd",
    subset: %w(mail.yml things.yml widgets_deprecated.yml), clean_up: false) do |f|
      mail = f.dig("mail.yml", "CustomResourceDefinition").first
      mail["metadata"]["annotations"] = {}

      things = f.dig("things.yml", "CustomResourceDefinition").first
      things["metadata"]["annotations"] = {
        "kubernetes-deploy.shopify.io/predeployed" => "true",
      }

      widgets = f.dig("widgets_deprecated.yml", "CustomResourceDefinition").first
      widgets["metadata"]["annotations"] = {
        "kubernetes-deploy.shopify.io/predeployed" => "false",
      }
    end)
    reset_logger


    result = deploy_fixtures("crd", subset: %w(mail_cr.yml things_cr.yml widgets_cr.yml)) do |f|
      f.each do |_filename, contents|
        contents.each do |kind, crs| # all of the resources are CRs, so change all of them
          crs.each { |cr| cr["kind"] = add_unique_prefix_for_test(cr["kind"]) }
        end
      end
    end
    assert_deploy_success(result)

    mail_cr_id = "#{add_unique_prefix_for_test("Mail")}/my-first-mail"
    thing_cr_id = "#{add_unique_prefix_for_test("Thing")}/my-first-thing"
    widget_cr_id = "#{add_unique_prefix_for_test("Widget")}/my-first-widget"
    assert_logs_match_all([
      /Phase 3: Predeploying priority resources/,
      %r{Successfully deployed in \d.\ds: #{mail_cr_id}},
      %r{Successfully deployed in \d.\ds: #{thing_cr_id}},
      /Phase 4: Deploying all resources/,
      %r{Successfully deployed in \d.\ds: #{mail_cr_id}, #{thing_cr_id}, #{widget_cr_id}},
    ], in_order: true)
    refute_logs_match(
      %r{Successfully deployed in \d.\ds: #{widget_cr_id}},
    )
  ensure
    wait_for_all_crd_deletion
  end

  def test_custom_resources_predeployed
    assert_deploy_success(deploy_global_fixtures("crd", subset: %w(mail.yml things.yml widgets.yml),
    clean_up: false) do |f|
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
        contents.each do |kind, crs| # all of the resources are CRs, so change all of them
          crs.each { |cr| cr["kind"] = add_unique_prefix_for_test(cr["kind"]) }
        end
      end
    end
    assert_deploy_success(result)

    mail_cr_id = "#{add_unique_prefix_for_test("Mail")}/my-first-mail"
    thing_cr_id = "#{add_unique_prefix_for_test("Thing")}/my-first-thing"
    widget_cr_id = "#{add_unique_prefix_for_test("Widget")}/my-first-widget"
    assert_logs_match_all([
      /Phase 3: Predeploying priority resources/,
      %r{Successfully deployed in \d.\ds: #{mail_cr_id}},
      %r{Successfully deployed in \d.\ds: #{thing_cr_id}},
      /Phase 4: Deploying all resources/,
      %r{Successfully deployed in \d.\ds: #{mail_cr_id}, #{thing_cr_id}, #{widget_cr_id}},
    ], in_order: true)
    refute_logs_match(
      %r{Successfully deployed in \d.\ds: #{widget_cr_id}},
    )
  ensure
    wait_for_all_crd_deletion
  end

  def test_stage_related_metrics_include_custom_tags_from_namespace
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    kubeclient.patch_namespace(hello_cloud.namespace, metadata: { labels: { foo: 'bar' } })
    metrics = capture_statsd_calls(client: Krane::StatsD.client) do
      assert_deploy_success deploy_fixtures("hello-cloud", subset: ["configmap-data.yml"], wait: false)
    end

    %w(
      Krane.validate_configuration.duration
      Krane.discover_resources.duration
      Krane.validate_resources.duration
      Krane.initial_status.duration
      Krane.priority_resources.duration
      Krane.apply_all.duration
      Krane.normal_resources.duration
      Krane.all_resources.duration
    ).each do |expected_metric|
      metric = metrics.find { |m| m.name == expected_metric }
      refute_nil metric, "Metric #{expected_metric} not emitted"
      assert_includes metric.tags, "foo:bar", "Metric #{expected_metric} did not have custom tags"
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
      Krane.initial_status.duration
      Krane.validate_resources.duration
      Krane.priority_resources.duration
      Krane.apply_all.duration
      Krane.normal_resources.duration
      Krane.sync.duration
      Krane.all_resources.duration
    ).each do |expected_metric|
      metric = metrics.find { |m| m.name == expected_metric }
      refute_nil metric, "Metric #{expected_metric} not emitted"
      assert_includes metric.tags, "namespace:#{@namespace}", "#{metric.name} is missing namespace tag"
      assert_includes metric.tags, "context:#{KubeclientHelper::TEST_CONTEXT}", "#{metric.name} is missing context tag"
      assert_includes metric.tags, "sha:test-sha", "#{metric.name} is missing sha tag"
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
      Krane.initial_status.duration
      Krane.validate_resources.duration
      Krane.apply_all.duration
      Krane.normal_resources.duration
      Krane.sync.duration
      Krane.all_resources.duration
    ).each do |expected_metric|
      metric = metrics.find { |m| m.name == expected_metric }
      refute_nil metric, "Metric #{expected_metric} not emitted"
      assert_includes metric.tags, "context:#{KubeclientHelper::TEST_CONTEXT}", "#{metric.name} is missing context tag"
    end
  end

  def test_cr_deploys_without_rollout_conditions_when_none_present_deprecated
    assert_deploy_success(deploy_global_fixtures("crd",
      subset: %(widgets_deprecated.yml), clean_up: false))
    result = deploy_fixtures("crd", subset: %w(widgets_cr.yml), prune: false) do |fixtures|
      cr = fixtures["widgets_cr.yml"]["Widget"].first
      cr["kind"] = add_unique_prefix_for_test(cr["kind"])
    end
    assert_deploy_success(result)

    prefixed_kind = add_unique_prefix_for_test("Widget")
    assert_logs_match_all([
      "Don't know how to monitor resources of type #{prefixed_kind}.",
      "Assuming #{prefixed_kind}/my-first-widget deployed successfully.",
      %r{#{prefixed_kind}/my-first-widget\s+Exists},
    ])
  ensure
    wait_for_all_crd_deletion
  end

  def test_cr_deploys_without_rollout_conditions_when_none_present
    assert_deploy_success(deploy_global_fixtures("crd", subset: %(widgets.yml), clean_up: false))
    result = deploy_fixtures("crd", subset: %w(widgets_cr.yml), prune: false) do |f|
      f.each do |_filename, contents| # all of the resources are CRs, so change all of them
        contents.each do |kind, crs|
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
  ensure
    wait_for_all_crd_deletion
  end

  def test_cr_success_with_default_rollout_conditions
    assert_deploy_success(deploy_global_fixtures("crd", subset: %(with_default_conditions.yml), clean_up: false))
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

    result = deploy_fixtures("crd", subset: ["with_default_conditions_cr.yml"], prune: false) do |resource|
      cr = resource["with_default_conditions_cr.yml"]["Parameterized"].first
      cr.merge!(success_conditions)
      cr["kind"] = add_unique_prefix_for_test(cr["kind"])
    end
    assert_deploy_success(result)
    assert_logs_match_all([
      %r{Successfully deployed in .*: #{add_unique_prefix_for_test("Parameterized")}\/with-default-params},
      %r{Parameterized/with-default-params\s+Healthy},
    ])
  ensure
    wait_for_all_crd_deletion
  end

  def test_cr_success_with_default_rollout_conditions_deprecated_annotation
    assert_deploy_success(deploy_global_fixtures("crd",
      subset: %(with_default_conditions_deprecated.yml), clean_up: false))
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
  ensure
    wait_for_all_crd_deletion
  end

  def test_cr_failure_with_default_rollout_conditions
    assert_deploy_success(deploy_global_fixtures("crd", subset: %(with_default_conditions.yml), clean_up: false))
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
  ensure
    wait_for_all_crd_deletion
  end

  def test_cr_success_with_arbitrary_rollout_conditions
    assert_deploy_success(deploy_global_fixtures("crd", subset: %(with_custom_conditions.yml), clean_up: false))

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
  ensure
    wait_for_all_crd_deletion
  end

  def test_cr_failure_with_arbitrary_rollout_conditions
    assert_deploy_success(deploy_global_fixtures("crd",
      subset: %(with_custom_conditions.yml), clean_up: false))
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
  ensure
    wait_for_all_crd_deletion
  end

  def test_deploying_crs_with_invalid_crd_conditions_fails
    # Since CRDs are not always deployed along with their CRs and krane is not the only way CRDs are
    # deployed, we need to model the case where poorly configured rollout_conditions are present before deploying a CR
    fixtures = load_fixtures("crd", "with_custom_conditions.yml")
    crd = fixtures["with_custom_conditions.yml"]["CustomResourceDefinition"].first
    crd["metadata"]["annotations"].merge!(Krane::CustomResourceDefinition::ROLLOUT_CONDITIONS_ANNOTATION => "blah")
    apply_scope_to_resources(fixtures, labels: "app=krane,test=#{@namespace}")
    Tempfile.open([@namespace, ".yml"]) do |f|
      f.write(YAML.dump(crd))
      f.fsync
      out, err, st = build_kubectl.run("create", "-f", f.path, log_failure: true, use_namespace: false)
      assert(st.success?, "Failed to create invalid CRD: #{out}\n#{err}")
    end

    result = deploy_fixtures("crd", subset: ["with_custom_conditions_cr.yml", "with_custom_conditions_cr2.yml"]) do |f|
      f.each do |_filename, contents|
        contents.each do |kind, crs| # all of the resources are CRs, so change all of them
          crs.each { |cr| cr["kind"] = add_unique_prefix_for_test(cr["kind"]) }
        end
      end
    end
    assert_deploy_failure(result)
    prefixed_name = add_unique_prefix_for_test("Customized-with-customized-params")
    assert_logs_match_all([
      /Invalid template: #{prefixed_name}/,
      /Rollout conditions are not valid JSON/,
      /Invalid template: #{prefixed_name}/,
      /Rollout conditions are not valid JSON/,
    ], in_order: true)
  ensure
    wait_for_all_crd_deletion
  end

  # We want to be sure that failures to apply resources with potentially sensitive output don't leak any content.
  # Currently our only sensitive resource is `Secret`, but we cannot reproduce a failure scenario where the kubectl
  # output contains the filename (which would trigger some extra logging). This test stubs `Deployment` to be sensitive
  # to recreate such a condition
  def test_apply_failure_with_sensitive_resources_hides_template_content
    logger.level = 0
    Krane::Deployment.any_instance.expects(:sensitive_template_content?).returns(true).at_least_once
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
      /Invalid template: Deployment-web.*\.yml/,
    ])

    refute_logs_match("kind: Deployment") # content of the sensitive template
  end

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

  def test_global_deploy_validation_catches_namespaced_cr
    assert_deploy_success(deploy_global_fixtures("crd", subset: %(mail.yml), clean_up: false))
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
      "#{add_unique_prefix_for_test('my-first-mail')} (#{add_unique_prefix_for_test('Mail')})",
    ])
  ensure
    wait_for_all_crd_deletion
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

  # Note: These tests assume a default storage class with a dynamic provisioner and 'Immediate' bind
  def test_pvc
    pvname = "local0001"
    storage_class_name = nil

    result = deploy_global_fixtures("pvc", subset: ["wait_for_first_consumer_storage_class.yml"], clean_up: false) do |fixtures|
      sc = fixtures["wait_for_first_consumer_storage_class.yml"]["StorageClass"].first
      storage_class_name = sc["metadata"]["name"] # will be made unique by the test helper
    end
    assert_deploy_success(result)
    TestProvisioner.prepare_pv(pvname, storage_class_name: storage_class_name)

    result = deploy_fixtures("pvc", subset: %w(pod.yml pvc.yml)) do |fixtures|
      pvc = fixtures["pvc.yml"]["PersistentVolumeClaim"].find { |pvc| pvc["metadata"]["name"] = "with-storage-class" }
      pvc["spec"]["storageClassName"] = storage_class_name
    end
    assert_deploy_success(result)

    assert_logs_match_all([
      "Successfully deployed 3 resource",
      "Successful resources",
      %r{PersistentVolumeClaim/with-storage-class\s+Bound},
      %r{PersistentVolumeClaim/without-storage-class\s+Bound},
      %r{Pod/pvc\s+Succeeded},
    ], in_order: true)

  ensure
    kubeclient.delete_persistent_volume(pvname)
    storage_v1_kubeclient.delete_storage_class(storage_class_name)
  end

  def test_pvc_no_bind
    pvname = "local0002"
    storage_class_name = nil

    result = deploy_global_fixtures("pvc", subset: ["wait_for_first_consumer_storage_class.yml"],
      clean_up: false) do |fixtures|
      sc = fixtures["wait_for_first_consumer_storage_class.yml"]["StorageClass"].first
      storage_class_name = sc["metadata"]["name"] # will be made unique by the test helper
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
    storage_class_name = nil

    result = deploy_global_fixtures("pvc", subset: ["wait_for_first_consumer_storage_class.yml"], clean_up: false) do |fixtures|
      sc = fixtures["wait_for_first_consumer_storage_class.yml"]["StorageClass"].first
      storage_class_name = sc["metadata"]["name"] # will be made unique by the test helper
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
  end

  def test_pvc_no_pv
    storage_class_name = nil

    result = deploy_global_fixtures("pvc",
    subset: ["wait_for_first_consumer_storage_class.yml"], clean_up: false) do |fixtures|
      sc = fixtures["wait_for_first_consumer_storage_class.yml"]["StorageClass"].first
      storage_class_name = sc["metadata"]["name"] # will be made unique by the test helper
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

  private

  def wait_for_all_crd_deletion
    crds = apiextensions_v1beta1_kubeclient.get_custom_resource_definitions
    crds.each do |crd|
      apiextensions_v1beta1_kubeclient.delete_custom_resource_definition(crd.metadata.name)
    end
    sleep(0.5) until apiextensions_v1beta1_kubeclient.get_custom_resource_definitions.none?
  end
end
