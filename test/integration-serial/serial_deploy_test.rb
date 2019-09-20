# frozen_string_literal: true
require 'integration_test_helper'

class SerialDeployTest < KubernetesDeploy::IntegrationTest
  include StatsDHelper
  # This cannot be run in parallel because it either stubs a constant or operates in a non-exclusive namespace
  def test_deploying_to_protected_namespace_with_override_does_not_prune
    KubernetesDeploy::DeployTask.stub_const(:PROTECTED_NAMESPACES, [@namespace]) do
      assert_deploy_success(deploy_fixtures("hello-cloud", subset: ['configmap-data.yml', 'disruption-budgets.yml'],
        allow_protected_ns: true, prune: false))
      hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
      hello_cloud.assert_configmap_data_present
      hello_cloud.assert_poddisruptionbudget
      assert_logs_match_all([
        /cannot be pruned/,
        /Please do not deploy to #{@namespace} unless you really know what you are doing/,
      ])

      result = deploy_fixtures("hello-cloud", subset: ["disruption-budgets.yml"],
        allow_protected_ns: true, prune: false)
      assert_deploy_success(result)
      hello_cloud.assert_configmap_data_present # not pruned
      hello_cloud.assert_poddisruptionbudget
    end
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

  # This can be run in parallel if we allow passing the config file path to DeployTask.new
  # See https://github.com/Shopify/kubernetes-deploy/pull/428#pullrequestreview-209720675
  def test_unreachable_context
    old_config = ENV['KUBECONFIG']
    begin
      ENV['KUBECONFIG'] = File.join(__dir__, '../fixtures/kube-config/dummy_config.yml')
      kubectl_instance = build_kubectl(timeout: '0.1s')
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
    assert_deploy_success(deploy_fixtures("crd", subset: %w(mail.yml)))
    assert_deploy_success(deploy_fixtures("crd", subset: %w(mail_cr.yml)))
    result = deploy_fixtures("crd", subset: %w(mail_cr.yml)) do |f|
      mail = f.dig("mail_cr.yml", "Mail").first
      mail["spec"]["something"] = 5
    end
    assert_deploy_success(result)
  ensure
    wait_for_all_crd_deletion
  end

  def test_crd_can_fail
    result = deploy_fixtures("crd", subset: %w(mail.yml)) do |f|
      crd = f.dig("mail.yml", "CustomResourceDefinition").first
      names = crd.dig("spec", "names")
      names["listKind"] = 'Conflict'
    end
    assert_deploy_success(result)

    result = deploy_fixtures("crd", subset: %w(mail.yml)) do |f|
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

  def test_crd_pruning_deprecated
    assert_deploy_success(deploy_fixtures("crd", subset: %w(mail.yml widgets_deprecated.yml)))
    assert_logs_match_all([
      "Phase 1: Initializing deploy",
      "Detected non-namespaced resources which will never be pruned:",
      " - CustomResourceDefinition/mail.stable.example.io",
      "Phase 3: Deploying all resources",
      "CustomResourceDefinition/mail.stable.example.io (timeout: 120s)",
      %r{CustomResourceDefinition/mail.stable.example.io\s+Names accepted},
      "Template warning:",
      "kubernetes-deploy.shopify.io as a prefix for annotations is deprecated:",
    ])
    assert_deploy_success(deploy_fixtures("crd", subset: %w(mail_cr.yml widgets_cr.yml configmap-data.yml)))
    # Deploy any other non-priority (predeployable) resource to trigger pruning
    assert_deploy_success(deploy_fixtures("crd", subset: %w(configmap-data.yml configmap2.yml)))

    assert_predicate(build_kubectl.run("get", "mail.stable.example.io", "my-first-mail").last, :success?)
    refute_logs_match(
      /The following resources were pruned: #{prune_matcher("mail", "stable.example.io", "my-first-mail")}/
    )
    assert_logs_match_all([
      /The following resources were pruned: #{prune_matcher("widget", "stable.example.io", "my-first-widget")}/,
      "Pruned 1 resource and successfully deployed 2 resource",
    ])
  ensure
    wait_for_all_crd_deletion
  end

  def test_crd_pruning
    assert_deploy_success(deploy_fixtures("crd", subset: %w(mail.yml widgets.yml)))
    assert_logs_match_all([
      "Phase 1: Initializing deploy",
      "Detected non-namespaced resources which will never be pruned:",
      " - CustomResourceDefinition/mail.stable.example.io",
      "Phase 3: Deploying all resources",
      "CustomResourceDefinition/mail.stable.example.io (timeout: 120s)",
      %r{CustomResourceDefinition/mail.stable.example.io\s+Names accepted},
    ])
    assert_deploy_success(deploy_fixtures("crd", subset: %w(mail_cr.yml widgets_cr.yml configmap-data.yml)))
    # Deploy any other non-priority (predeployable) resource to trigger pruning
    assert_deploy_success(deploy_fixtures("crd", subset: %w(configmap-data.yml configmap2.yml)))

    assert_predicate(build_kubectl.run("get", "mail.stable.example.io", "my-first-mail").last, :success?)
    refute_logs_match(
      /The following resources were pruned: #{prune_matcher("mail", "stable.example.io", "my-first-mail")}/
    )
    assert_logs_match_all([
      /The following resources were pruned: #{prune_matcher("widget", "stable.example.io", "my-first-widget")}/,
      "Pruned 1 resource and successfully deployed 2 resource",
    ])
  ensure
    wait_for_all_crd_deletion
  end

  def test_custom_resources_predeployed_deprecated
    assert_deploy_success(deploy_fixtures("crd", subset: %w(mail.yml things.yml widgets_deprecated.yml)) do |f|
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
    assert_deploy_success(deploy_fixtures("crd", subset: %w(mail_cr.yml things_cr.yml widgets_cr.yml)))
    assert_logs_match_all([
      /Phase 3: Predeploying priority resources/,
      %r{Successfully deployed in \d.\ds: Mail/my-first-mail},
      %r{Successfully deployed in \d.\ds: Thing/my-first-thing},
      /Phase 4: Deploying all resources/,
      %r{Successfully deployed in \d.\ds: Mail/my-first-mail, Thing/my-first-thing, Widget/my-first-widget},
    ], in_order: true)
    refute_logs_match(
      %r{Successfully deployed in \d.\ds: Widget/my-first-widget},
    )
  ensure
    wait_for_all_crd_deletion
  end

  def test_custom_resources_predeployed
    assert_deploy_success(deploy_fixtures("crd", subset: %w(mail.yml things.yml widgets.yml)) do |f|
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
    assert_deploy_success(deploy_fixtures("crd", subset: %w(mail_cr.yml things_cr.yml widgets_cr.yml)))
    assert_logs_match_all([
      /Phase 3: Predeploying priority resources/,
      %r{Successfully deployed in \d.\ds: Mail/my-first-mail},
      %r{Successfully deployed in \d.\ds: Thing/my-first-thing},
      /Phase 4: Deploying all resources/,
      %r{Successfully deployed in \d.\ds: Mail/my-first-mail, Thing/my-first-thing, Widget/my-first-widget},
    ], in_order: true)
    refute_logs_match(
      %r{Successfully deployed in \d.\ds: Widget/my-first-widget},
    )
  ensure
    wait_for_all_crd_deletion
  end

  def test_stage_related_metrics_include_custom_tags_from_namespace
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    kubeclient.patch_namespace(hello_cloud.namespace, metadata: { labels: { foo: 'bar' } })
    metrics = capture_statsd_calls do
      assert_deploy_success deploy_fixtures("hello-cloud", subset: ["configmap-data.yml"], wait: false)
    end

    %w(
      KubernetesDeploy.validate_configuration.duration
      KubernetesDeploy.discover_resources.duration
      KubernetesDeploy.validate_resources.duration
      KubernetesDeploy.initial_status.duration
      KubernetesDeploy.priority_resources.duration
      KubernetesDeploy.apply_all.duration
      KubernetesDeploy.normal_resources.duration
      KubernetesDeploy.all_resources.duration
    ).each do |expected_metric|
      metric = metrics.find { |m| m.name == expected_metric }
      refute_nil metric, "Metric #{expected_metric} not emitted"
      assert_includes metric.tags, "foo:bar", "Metric #{expected_metric} did not have custom tags"
    end
  end

  def test_all_expected_statsd_metrics_emitted_with_essential_tags
    metrics = capture_statsd_calls do
      result = deploy_fixtures('hello-cloud', subset: ['configmap-data.yml'], wait: false, sha: 'test-sha')
      assert_deploy_success(result)
    end

    assert_equal(1, metrics.count { |m| m.type == :_e }, "Expected to find one event metric")

    %w(
      KubernetesDeploy.validate_configuration.duration
      KubernetesDeploy.discover_resources.duration
      KubernetesDeploy.validate_resources.duration
      KubernetesDeploy.initial_status.duration
      KubernetesDeploy.priority_resources.duration
      KubernetesDeploy.apply_all.duration
      KubernetesDeploy.normal_resources.duration
      KubernetesDeploy.sync.duration
      KubernetesDeploy.all_resources.duration
    ).each do |expected_metric|
      metric = metrics.find { |m| m.name == expected_metric }
      refute_nil metric, "Metric #{expected_metric} not emitted"
      assert_includes metric.tags, "namespace:#{@namespace}", "#{metric.name} is missing namespace tag"
      assert_includes metric.tags, "context:#{KubeclientHelper::TEST_CONTEXT}", "#{metric.name} is missing context tag"
      assert_includes metric.tags, "sha:test-sha", "#{metric.name} is missing sha tag"
    end
  end

  def test_cr_deploys_without_rollout_conditions_when_none_present_deprecated
    assert_deploy_success(deploy_fixtures("crd", subset: %w(widgets_deprecated.yml)))
    assert_deploy_success(deploy_fixtures("crd", subset: %w(widgets_cr.yml)))
    assert_logs_match_all([
      "Don't know how to monitor resources of type Widget. Assuming Widget/my-first-widget deployed successfully.",
      %r{Widget/my-first-widget\s+Exists},
    ])
  ensure
    wait_for_all_crd_deletion
  end

  def test_cr_deploys_without_rollout_conditions_when_none_present
    assert_deploy_success(deploy_fixtures("crd", subset: %w(widgets.yml)))
    assert_deploy_success(deploy_fixtures("crd", subset: %w(widgets_cr.yml)))
    assert_logs_match_all([
      "Don't know how to monitor resources of type Widget. Assuming Widget/my-first-widget deployed successfully.",
      %r{Widget/my-first-widget\s+Exists},
    ])
  ensure
    wait_for_all_crd_deletion
  end

  def test_cr_success_with_default_rollout_conditions
    assert_deploy_success(deploy_fixtures("crd", subset: ["with_default_conditions.yml"]))
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
    end
    assert_deploy_success(result)
    assert_logs_match_all([
      %r{Successfully deployed in .*: Parameterized\/with-default-params},
      %r{Parameterized/with-default-params\s+Healthy},
    ])
  ensure
    wait_for_all_crd_deletion
  end

  def test_cr_succes_with_default_rollout_conditions_deprecated_annotation
    assert_deploy_success(deploy_fixtures("crd", subset: ["with_default_conditions_deprecated.yml"]))
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
    end
    assert_deploy_success(result)
    assert_logs_match_all([
      %r{Successfully deployed in .*: Parameterized\/with-default-params},
      %r{Parameterized/with-default-params\s+Healthy},
    ])
  ensure
    wait_for_all_crd_deletion
  end

  def test_cr_failure_with_default_rollout_conditions
    assert_deploy_success(deploy_fixtures("crd", subset: ["with_default_conditions.yml"]))
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
    assert_deploy_success(deploy_fixtures("crd", subset: ["with_custom_conditions.yml"]))

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
      cr.merge!(success_conditions)
    end
    assert_deploy_success(result)
    assert_logs_match_all([
      %r{Successfully deployed in .*: Customized\/with-customized-params},
    ])
  ensure
    wait_for_all_crd_deletion
  end

  def test_cr_failure_with_arbitrary_rollout_conditions
    assert_deploy_success(deploy_fixtures("crd", subset: ["with_custom_conditions.yml"]))
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
    # Since CRDs are not always deployed along with their CRs and kubernetes-deploy is not the only way CRDs are
    # deployed, we need to model the case where poorly configured rollout_conditions are present before deploying a CR
    KubernetesDeploy::DeployTask.any_instance.expects(:validate_resources).returns(:true)
    crd_result = deploy_fixtures("crd", subset: ["with_custom_conditions.yml"]) do |resource|
      crd = resource["with_custom_conditions.yml"]["CustomResourceDefinition"].first
      crd["metadata"]["annotations"].merge!(
        KubernetesDeploy::CustomResourceDefinition::ROLLOUT_CONDITIONS_ANNOTATION => "blah"
      )
    end

    assert_deploy_success(crd_result)
    KubernetesDeploy::DeployTask.any_instance.unstub(:validate_resources)

    cr_result = deploy_fixtures("crd", subset: ["with_custom_conditions_cr.yml", "with_custom_conditions_cr2.yml"])
    assert_deploy_failure(cr_result)
    assert_logs_match_all([
      /Invalid template: Customized-with-customized-params/,
      /Rollout conditions are not valid JSON/,
      /Invalid template: Customized-with-customized-params/,
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
    KubernetesDeploy::Deployment.any_instance.expects(:sensitive_template_content?).returns(true).at_least_once
    result = deploy_fixtures("hello-cloud", subset: ["web.yml.erb"]) do |fixtures|
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

  private

  def wait_for_all_crd_deletion
    crds = apiextensions_v1beta1_kubeclient.get_custom_resource_definitions
    crds.each do |crd|
      apiextensions_v1beta1_kubeclient.delete_custom_resource_definition(crd.metadata.name)
    end
    sleep(0.5) until apiextensions_v1beta1_kubeclient.get_custom_resource_definitions.none?
  end
end
