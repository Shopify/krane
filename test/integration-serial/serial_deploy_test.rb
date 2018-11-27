# frozen_string_literal: true
require 'integration_test_helper'

class SerialDeployTest < KubernetesDeploy::IntegrationTest
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
        /Please do not deploy to #{@namespace} unless you really know what you are doing/
      ])

      result = deploy_fixtures("hello-cloud", subset: ["disruption-budgets.yml"],
        allow_protected_ns: true, prune: false)
      assert_deploy_success(result)
      hello_cloud.assert_configmap_data_present # not pruned
      hello_cloud.assert_poddisruptionbudget
    end
  end

  # This cannot be run in parallel because it needs to manipulate the global log level
  def test_create_and_update_secrets_from_ejson
    logger.level = ::Logger::DEBUG # for assertions that we don't log secret data

    # Create secrets
    ejson_cloud = FixtureSetAssertions::EjsonCloud.new(@namespace)
    ejson_cloud.create_ejson_keys_secret
    assert_deploy_success(deploy_fixtures("ejson-cloud"))
    ejson_cloud.assert_all_up
    assert_logs_match_all([
      /Creating secret catphotoscom/,
      /Creating secret unused-secret/,
      /Creating secret monitoring-token/
    ])

    refute_logs_match(ejson_cloud.test_private_key)
    refute_logs_match(ejson_cloud.test_public_key)
    refute_logs_match(Base64.strict_encode64(ejson_cloud.catphotoscom_key_value))

    # Update secrets
    result = deploy_fixtures("ejson-cloud") do |fixtures|
      fixtures["secrets.ejson"]["kubernetes_secrets"]["unused-secret"]["data"] = { "_test" => "a" }
    end
    assert_deploy_success(result)
    ejson_cloud.assert_secret_present('unused-secret', { "test" => "a" }, managed: true)
    ejson_cloud.assert_web_resources_up
    assert_logs_match(/Updating secret unused-secret/)

    refute_logs_match(ejson_cloud.test_private_key)
    refute_logs_match(ejson_cloud.test_public_key)
    refute_logs_match(Base64.strict_encode64(ejson_cloud.catphotoscom_key_value))
  end

  # This can be run in parallel when we switch to --kubeconfig (https://github.com/Shopify/kubernetes-deploy/issues/52)
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

  # This can be run in parallel when we switch to --kubeconfig (https://github.com/Shopify/kubernetes-deploy/issues/52)
  def test_multiple_configuration_files
    old_config = ENV['KUBECONFIG']
    config_file = File.join(__dir__, '../fixtures/kube-config/unknown_config.yml')
    ENV['KUBECONFIG'] = config_file
    result = deploy_fixtures('hello-cloud')
    assert_deploy_failure(result)
    assert_logs_match_all([
      'Result: FAILURE',
      'Configuration invalid',
      "Kube config not found at #{config_file}"
    ], in_order: true)
    reset_logger

    ENV['KUBECONFIG'] = " : "
    result = deploy_fixtures('hello-cloud')
    assert_deploy_failure(result)
    assert_logs_match_all([
      'Result: FAILURE',
      'Configuration invalid',
      "Kube config file name(s) not set in $KUBECONFIG"
    ], in_order: true)
    reset_logger

    ENV['KUBECONFIG'] = nil
    result = deploy_fixtures('hello-cloud')
    assert_deploy_failure(result)
    assert_logs_match_all([
      'Result: FAILURE',
      'Configuration invalid',
      "$KUBECONFIG not set"
    ], in_order: true)
    reset_logger

    extra_config = File.join(__dir__, '../fixtures/kube-config/dummy_config.yml')
    ENV['KUBECONFIG'] = "#{old_config}:#{extra_config}"
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
      'Final status: ListKindConflict ("Conflict" is already in use)'
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
      %r{CustomResourceDefinition/mail.stable.example.io\s+Names accepted}
    ])
    assert_deploy_success(deploy_fixtures("crd", subset: %w(mail_cr.yml widgets_cr.yml configmap-data.yml)))
    # Deploy any other non-priority (predeployable) resource to trigger pruning
    assert_deploy_success(deploy_fixtures("crd", subset: %w(configmap-data.yml configmap2.yml)))

    assert_predicate build_kubectl.run("get", "mail.stable.example.io", "my-first-mail").last, :success?
    refute_logs_match(
      /The following resources were pruned: #{prune_matcher("mail", "stable.example.io", "my-first-mail")}/
    )
    assert_logs_match_all([
      /The following resources were pruned: #{prune_matcher("widget", "stable.example.io", "my-first-widget")}/,
      "Pruned 1 resource and successfully deployed 2 resource"
    ])
  ensure
    wait_for_all_crd_deletion
  end

  def test_stage_related_metrics_include_custom_tags_from_namespace
    hello_cloud = FixtureSetAssertions::HelloCloud.new(@namespace)
    kubeclient.patch_namespace(hello_cloud.namespace, metadata: { labels: { foo: 'bar' } })
    metrics = StatsDHelper.capture_statsd_calls do
      assert_deploy_success deploy_fixtures("hello-cloud", subset: ["configmap-data.yml"], wait: false)
    end

    %w(
      KubernetesDeploy.validate_configuration.duration
      KubernetesDeploy.discover_resources.duration
      KubernetesDeploy.validate_resources.duration
      KubernetesDeploy.initial_status.duration
      KubernetesDeploy.create_ejson_secrets.duration
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
    metrics = StatsDHelper.capture_statsd_calls do
      result = deploy_fixtures('hello-cloud', subset: ['configmap-data.yml'], wait: false)
      assert_deploy_success(result)
    end

    assert_equal 1, metrics.count { |m| m.type == :_e }, "Expected to find one event metric"
    assert_predicate metrics, :all? do |metric|
      assert_includes metric.tags, "namespace:#{@namespace}"
      assert_includes metric.tags, "context:#{KubeclientHelper::TEST_CONTEXT}"
    end

    %w(
      KubernetesDeploy.validate_configuration.duration
      KubernetesDeploy.discover_resources.duration
      KubernetesDeploy.validate_resources.duration
      KubernetesDeploy.initial_status.duration
      KubernetesDeploy.create_ejson_secrets.duration
      KubernetesDeploy.priority_resources.duration
      KubernetesDeploy.apply_all.duration
      KubernetesDeploy.normal_resources.duration
      KubernetesDeploy.sync.duration
      KubernetesDeploy.all_resources.duration
    ).each do |expected_metric|
      metric = metrics.find { |m| m.name == expected_metric }
      refute_nil metric, "Metric #{expected_metric} not emitted"
    end
  end

  private

  def wait_for_all_crd_deletion
    crds = apiextensions_v1beta1_kubeclient.get_custom_resource_definitions
    crds.each do |crd|
      apiextensions_v1beta1_kubeclient.delete_custom_resource_definition(crd.metadata.name)
    end
    sleep 0.5 until apiextensions_v1beta1_kubeclient.get_custom_resource_definitions.none?
  end
end
