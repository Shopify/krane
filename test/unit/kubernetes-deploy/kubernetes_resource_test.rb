# frozen_string_literal: true
require 'test_helper'

class KubernetesResourceTest < KubernetesDeploy::TestCase
  include EnvTestHelper

  class DummyResource < KubernetesDeploy::KubernetesResource
    attr_writer :succeeded, :deploy_failed

    def initialize(definition_extras: {})
      definition = { "kind" => "DummyResource", "metadata" => { "name" => "test" } }.merge(definition_extras)
      super(namespace: 'test', context: 'test', definition: definition, logger: ::Logger.new($stderr))
      @succeeded = false
    end

    def exists?
      true
    end

    def deploy_failed?
      @deploy_failed
    end

    def fetch_debug_logs(_kubectl)
      {}
    end

    def print_debug_logs?
      true
    end

    def deploy_succeeded?
      @succeeded
    end

    def file_path
      "/tmp/foo/bar"
    end
  end

  class DummySensitiveResource < DummyResource
    SENSITIVE_TEMPLATE_CONTENT = true
    SERVER_DRY_RUNNABLE = true
  end

  def test_unusual_timeout_output
    spec = { "kind" => "ConfigMap", "metadata" => { "name" => "foo" } }
    cm = KubernetesDeploy::ConfigMap.new(namespace: 'foo', context: 'none', definition: spec, logger: logger)
    cm.deploy_started_at = Time.now.utc

    Timecop.freeze(Time.now.utc + 60) do
      assert cm.deploy_timed_out?
      expected = <<~STRING
        It is very unusual for this resource type to fail to deploy. Please try the deploy again.
        If that new deploy also fails, contact your cluster administrator.
      STRING
      assert_equal expected, cm.timeout_message
    end
  end

  def test_service_and_deployment_timeouts_are_equal
    message = "Service and Deployment timeouts have to match since services are waiting to get endpoints " \
      "from their backing deployments"
    assert_equal(KubernetesDeploy::Service.timeout, KubernetesDeploy::Deployment.timeout, message)
  end

  def test_fetch_events_parses_tricky_events_correctly
    start_time = Time.now.utc - 10.seconds
    dummy = DummyResource.new
    dummy.deploy_started_at = start_time

    tricky_events = dummy_events(start_time)
    assert(tricky_events.first[:message].count("\n") > 1, "Sanity check failed: inadequate newlines in test events")

    kubectl.expects(:run).returns([build_event_jsonpath(tricky_events), "", SystemExit.new(0)])
    events = dummy.fetch_events(kubectl)
    assert_includes_dummy_events(events, first: true, second: true)
  end

  def test_fetch_events_excludes_events_from_previous_deploys
    start_time = Time.now.utc - 10.seconds
    dummy = DummyResource.new
    dummy.deploy_started_at = start_time
    mixed_time_events = dummy_events(start_time)
    mixed_time_events.first[:last_seen] = 1.hour.ago

    kubectl.expects(:run).returns([build_event_jsonpath(mixed_time_events), "", SystemExit.new(0)])
    events = dummy.fetch_events(kubectl)
    assert_includes_dummy_events(events, first: false, second: true)
  end

  def test_fetch_events_returns_empty_hash_when_kubectl_results_empty
    dummy = DummyResource.new
    dummy.deploy_started_at = Time.now.utc - 10.seconds

    kubectl.expects(:run).returns(["", "", SystemExit.new(0)])
    events = dummy.fetch_events(kubectl)
    assert_operator(events, :empty?)
  end

  def test_deprecated_annotation_generates_warning
    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata("60S", use_deprecated: true))
    customized_resource.validate_definition(kubectl)
    assert(customized_resource.has_warnings?, "Deprecated annotation did not generate a warning")
    assert_equal("kubernetes-deploy.shopify.io as a prefix for annotations is deprecated: "\
      "Use the 'krane.shopify.io' annotation prefix instead",
      customized_resource.validation_warning_msg)
  end

  def test_multiple_deprecated_annotations_generates_only_one_warning
    definition_extras = build_timeout_metadata("60S", use_deprecated: true).dup
    definition_extras['metadata']['annotations']['kubernetes-deploy.shopify.io/something'] = "thing"
    customized_resource = DummyResource.new(definition_extras: definition_extras)
    customized_resource.validate_definition(kubectl)

    warning_message = <<~MESSAGE.strip
      kubernetes-deploy.shopify.io as a prefix for annotations is deprecated: Use the 'krane.shopify.io' annotation prefix instead
    MESSAGE

    assert(customized_resource.has_warnings?, "Deprecated annotation did not generate a warning")
    assert_equal(customized_resource.validation_warning_msg, warning_message)
  end

  def test_valid_annotations_generate_no_warning
    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata("60S"))
    customized_resource.validate_definition(kubectl)
    refute(customized_resource.has_warnings?, "Valid annotation generated a warning")
  end

  def test_can_override_hardcoded_timeout_via_an_annotation_deprecated
    basic_resource = DummyResource.new
    assert_equal(300, basic_resource.timeout)

    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata("60S", use_deprecated: true))
    assert_equal(60, customized_resource.timeout)

    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata("60M", use_deprecated: true))
    assert_equal(3600, customized_resource.timeout)

    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata("1H", use_deprecated: true))
    assert_equal(3600, customized_resource.timeout)
  end

  def test_can_override_hardcoded_timeout_via_an_annotation
    basic_resource = DummyResource.new
    assert_equal(300, basic_resource.timeout)

    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata("60S"))
    assert_equal(60, customized_resource.timeout)

    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata("60M"))
    assert_equal(3600, customized_resource.timeout)

    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata("1H"))
    assert_equal(3600, customized_resource.timeout)
  end

  def test_blank_timeout_annotation_is_invalid_deprecated
    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata("", use_deprecated: true))
    customized_resource.validate_definition(kubectl)
    assert(customized_resource.validation_failed?, "Blank annotation was valid")
    assert_equal("#{timeout_override_err_prefix_deprecated}: Invalid ISO 8601 duration: \"\" is empty duration",
      customized_resource.validation_error_msg)
  end

  def test_blank_timeout_annotation_is_invalid
    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata(""))
    customized_resource.validate_definition(kubectl)
    assert(customized_resource.validation_failed?, "Blank annotation was valid")
    assert_equal("#{timeout_override_err_prefix}: Invalid ISO 8601 duration: \"\" is empty duration",
      customized_resource.validation_error_msg)
  end

  def test_lack_of_timeout_annotation_does_not_fail_validation
    basic_resource = DummyResource.new
    assert_equal(300, basic_resource.timeout)
    basic_resource.validate_definition(kubectl)
    refute(basic_resource.validation_failed?)
  end

  def test_timeout_override_lower_bound_validation_deprecation
    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata("-1S", use_deprecated: true))
    customized_resource.validate_definition(kubectl)
    assert(customized_resource.validation_failed?, "Annotation with '-1' was valid")
    assert_equal("#{timeout_override_err_prefix_deprecated}: Value must be greater than 0",
      customized_resource.validation_error_msg)

    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata("0S", use_deprecated: true))
    customized_resource.validate_definition(kubectl)
    assert(customized_resource.validation_failed?, "Annotation with '0' was valid")
    assert_equal("#{timeout_override_err_prefix_deprecated}: Value must be greater than 0",
      customized_resource.validation_error_msg)

    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata("1S", use_deprecated: true))
    customized_resource.validate_definition(kubectl)
    refute(customized_resource.validation_failed?, "Annotation with '1' was invalid")
  end

  def test_timeout_override_lower_bound_validation
    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata("-1S"))
    customized_resource.validate_definition(kubectl)
    assert(customized_resource.validation_failed?, "Annotation with '-1' was valid")
    assert_equal("#{timeout_override_err_prefix}: Value must be greater than 0",
      customized_resource.validation_error_msg)

    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata("0S"))
    customized_resource.validate_definition(kubectl)
    assert(customized_resource.validation_failed?, "Annotation with '0' was valid")
    assert_equal("#{timeout_override_err_prefix}: Value must be greater than 0",
      customized_resource.validation_error_msg)

    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata("1S"))
    customized_resource.validate_definition(kubectl)
    refute(customized_resource.validation_failed?, "Annotation with '1' was invalid")
  end

  def test_timeout_override_upper_bound_validation_deprecated
    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata("24H1S", use_deprecated: true))
    customized_resource.validate_definition(kubectl)
    assert(customized_resource.validation_failed?, "Annotation with '24H1S' was valid")
    expected_message = "#{timeout_override_err_prefix_deprecated}: Value must be less than 24h"
    assert_equal(expected_message, customized_resource.validation_error_msg)

    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata("24H", use_deprecated: true))
    customized_resource.validate_definition(kubectl)
    refute(customized_resource.validation_failed?, "Annotation with '24H' was invalid")
  end

  def test_timeout_override_upper_bound_validation
    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata("24H1S"))
    customized_resource.validate_definition(kubectl)
    assert(customized_resource.validation_failed?, "Annotation with '24H1S' was valid")
    expected_message = "#{timeout_override_err_prefix}: Value must be less than 24h"
    assert_equal(expected_message, customized_resource.validation_error_msg)

    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata("24H"))
    customized_resource.validate_definition(kubectl)
    refute(customized_resource.validation_failed?, "Annotation with '24H' was invalid")
  end

  def test_validate_definition_doesnt_log_raw_output_for_sensitive_resources
    resource = DummySensitiveResource.new
    kubectl.expects(:run).with { |*_args, **kwargs| kwargs[:output_is_sensitive] == true }.returns([
      "Some Raw Output",
      "Error from kubectl: something went wrong and by the way here's your secret: S3CR3T",
      stub(success?: false),
    ])
    resource.validate_definition(kubectl)
    refute_includes(resource.validation_error_msg, 'S3CR3T')
  end

  def test_annotation_and_kubectl_error_messages_are_combined_deprecated
    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata("bad", use_deprecated: true))
    kubectl.expects(:run).returns([
      "{}",
      "Error from kubectl: Something else in this template was not valid",
      stub(success?: false),
    ])

    customized_resource.validate_definition(kubectl)
    assert(customized_resource.validation_failed?, "Expected resource to be invalid")
    expected = <<~STRING.strip
      #{timeout_override_err_prefix_deprecated}: Invalid ISO 8601 duration: "BAD"
      Error from kubectl: Something else in this template was not valid
    STRING
    assert_equal(expected, customized_resource.validation_error_msg)
  end

  def test_annotation_and_kubectl_error_messages_are_combined
    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata("bad"))
    kubectl.expects(:run).returns([
      "{}",
      "Error from kubectl: Something else in this template was not valid",
      stub(success?: false),
    ])

    customized_resource.validate_definition(kubectl)
    assert(customized_resource.validation_failed?, "Expected resource to be invalid")
    expected = <<~STRING.strip
      #{timeout_override_err_prefix}: Invalid ISO 8601 duration: "BAD"
      Error from kubectl: Something else in this template was not valid
    STRING
    assert_equal(expected, customized_resource.validation_error_msg)
  end

  def test_calling_timeout_before_validation_with_invalid_annotation_does_not_raise_deprecated
    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata("bad", use_deprecated: true))
    assert_equal(300, customized_resource.timeout)
    assert_nil(customized_resource.timeout_override)
  end

  def test_calling_timeout_before_validation_with_invalid_annotation_does_not_raise
    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata("bad"))
    assert_equal(300, customized_resource.timeout)
    assert_nil(customized_resource.timeout_override)
  end

  def test_deploy_timed_out_respects_hardcoded_timeouts
    Timecop.freeze do
      dummy = DummyResource.new
      refute dummy.deploy_timed_out?
      assert_equal 300, dummy.timeout

      dummy.deploy_started_at = Time.now.utc - 300
      refute dummy.deploy_timed_out?

      dummy.deploy_started_at = Time.now.utc - 301
      assert dummy.deploy_timed_out?
    end
  end

  def test_deploy_timed_out_respects_annotation_based_timeouts_deprecated
    Timecop.freeze do
      custom_dummy = DummyResource.new(definition_extras: build_timeout_metadata("3s", use_deprecated: true))
      refute custom_dummy.deploy_timed_out?
      assert_equal 3, custom_dummy.timeout

      custom_dummy.deploy_started_at = Time.now.utc - 3
      refute custom_dummy.deploy_timed_out?

      custom_dummy.deploy_started_at = Time.now.utc - 4
      assert custom_dummy.deploy_timed_out?
    end
  end

  def test_deploy_timed_out_respects_annotation_based_timeouts
    Timecop.freeze do
      custom_dummy = DummyResource.new(definition_extras: build_timeout_metadata("3s"))
      refute custom_dummy.deploy_timed_out?
      assert_equal 3, custom_dummy.timeout

      custom_dummy.deploy_started_at = Time.now.utc - 3
      refute custom_dummy.deploy_timed_out?

      custom_dummy.deploy_started_at = Time.now.utc - 4
      assert custom_dummy.deploy_timed_out?
    end
  end

  def test_debug_message_with_no_log_info
    with_env(KubernetesDeploy::KubernetesResource::DISABLE_FETCHING_LOG_INFO, 'true') do
      dummy = DummyResource.new
      dummy.expects(:fetch_debug_logs).never
      dummy.deploy_failed = true

      assert_includes dummy.debug_message, "DummyResource/test: FAILED\n  - Final status: Exists\n"
      assert_includes dummy.debug_message, KubernetesDeploy::KubernetesResource::DISABLED_LOG_INFO_MESSAGE
    end
  end

  def test_debug_message_with_no_event_info
    with_env(KubernetesDeploy::KubernetesResource::DISABLE_FETCHING_EVENT_INFO, 'true') do
      dummy = DummyResource.new
      dummy.expects(:fetch_events).never
      dummy.deploy_failed = true

      assert_includes dummy.debug_message, "DummyResource/test: FAILED\n  - Final status: Exists\n"
      assert_includes dummy.debug_message, KubernetesDeploy::KubernetesResource::DISABLED_EVENT_INFO_MESSAGE
    end
  end

  def test_whitespace_in_debug_message
    dummy = DummyResource.new
    dummy.deploy_failed = true
    expected_message = <<~STRING
      DummyResource/test: FAILED
        - Final status: Exists
        - Events: None found. Please check your usual logging service (e.g. Splunk).
        - Logs: None found. Please check your usual logging service (e.g. Splunk).
    STRING
    assert_equal(expected_message.strip, dummy.debug_message)

    dummy.stubs(:failure_message).returns("Something went wrong I guess")

    expected_message = <<~STRING
      DummyResource/test: FAILED
      Something went wrong I guess

        - Final status: Exists
        - Events: None found. Please check your usual logging service (e.g. Splunk).
        - Logs: None found. Please check your usual logging service (e.g. Splunk).
    STRING
    assert_equal(expected_message.strip, dummy.debug_message)

    dummy.stubs(:failure_message).returns("Something went wrong I guess\n> Some container: boom!\n")

    expected_message = <<~STRING
      DummyResource/test: FAILED
      Something went wrong I guess
      > Some container: boom!

        - Final status: Exists
        - Events: None found. Please check your usual logging service (e.g. Splunk).
        - Logs: None found. Please check your usual logging service (e.g. Splunk).
    STRING
    assert_equal(expected_message.strip, dummy.debug_message)
  end

  def test_disappeared_is_true_if_resource_has_been_deployed_and_404s
    dummy = DummyResource.new
    cache = KubernetesDeploy::ResourceCache.new('test', 'minikube', logger)
    cache.expects(:get_instance).raises(KubernetesDeploy::Kubectl::ResourceNotFoundError).twice

    dummy.sync(cache)
    refute_predicate(dummy, :disappeared?)

    dummy.deploy_started_at = Time.now.utc
    dummy.sync(cache)
    assert_predicate(dummy, :disappeared?)
  end

  def test_disappeared_is_false_if_resource_has_been_deployed_and_we_get_a_server_error
    dummy = DummyResource.new
    cache = KubernetesDeploy::ResourceCache.new('test', 'minikube', logger)
    KubernetesDeploy::Kubectl.any_instance.expects(:run).returns(["", "NotFound", stub(success?: false)]).twice

    dummy.sync(cache)
    refute_predicate(dummy, :disappeared?)

    dummy.deploy_started_at = Time.now.utc
    dummy.sync(cache)
    refute_predicate(dummy, :disappeared?)
  end

  def test_lowercase_custom_resource_kind_does_not_raise
    definition = { "kind" => "foobar", "metadata" => { "name" => "test" } }
    KubernetesDeploy::KubernetesResource.build(
      namespace: 'test',
      context: 'test',
      definition: definition,
      logger: logger,
      statsd_tags: []
    )
  end

  def test_build_handles_hardcoded_and_core_and_dynamic_objects
    # Hardcoded CRs
    cloudsql_crd = KubernetesDeploy::KubernetesResource.build(namespace: "test", context: "test",
      logger: @logger, statsd_tags: [], definition: build_crd(name: "cloudsql"))
    cloudsql_cr = KubernetesDeploy::KubernetesResource.build(namespace: "test", context: "test",
      logger: @logger, statsd_tags: [], crd: cloudsql_crd,
      definition: { "kind" => "Cloudsql", "metadata" => { "name" => "test" } })
    assert_equal(cloudsql_cr.class, KubernetesDeploy::Cloudsql)

    # Dynamic with no rollout config
    no_config_crd = KubernetesDeploy::KubernetesResource.build(namespace: "test", context: "test",
      logger: @logger, statsd_tags: [], definition: build_crd(name: "noconfig"))
    no_config_cr = KubernetesDeploy::KubernetesResource.build(namespace: "test", context: "test",
      logger: @logger, statsd_tags: [], crd: no_config_crd,
      definition: { "kind" => "Noconfig", "metadata" => { "name" => "test" } })
    assert_equal(no_config_cr.class, KubernetesDeploy::CustomResource)

    # With rollout config
    with_config_crd = KubernetesDeploy::KubernetesResource.build(namespace: "test", context: "test",
      logger: @logger, statsd_tags: [], definition: build_crd(name: "withconfig", with_config: true))
    with_config_cr = KubernetesDeploy::KubernetesResource.build(namespace: "test", context: "test",
      logger: @logger, statsd_tags: [], crd: with_config_crd,
      definition: { "kind" => "Withconfig", "metadata" => { "name" => "test" } })
    assert_equal(with_config_cr.class, KubernetesDeploy::CustomResource)

    # Hardcoded resource
    svc = KubernetesDeploy::KubernetesResource.build(namespace: "test", context: "test", logger: @logger,
      statsd_tags: [], definition: { "kind" => "Service", "metadata" => { "name" => "test" } })
    assert_equal(svc.class, KubernetesDeploy::Service)

    # Generic resource
    resource = KubernetesDeploy::KubernetesResource.build(namespace: "test", context: "test", logger: @logger,
      statsd_tags: [], definition: { "kind" => "Unkonwn", "metadata" => { "name" => "test" } })
    assert_equal(resource.class, KubernetesDeploy::KubernetesResource)
  end

  private

  def kubectl
    @kubectl ||= build_runless_kubectl
  end

  def timeout_override_err_prefix_deprecated
    "kubernetes-deploy.shopify.io/timeout-override annotation is invalid"
  end

  def timeout_override_err_prefix
    "krane.shopify.io/timeout-override annotation is invalid"
  end

  def build_timeout_metadata(value, use_deprecated: false)
    timeout_override_annotation = if use_deprecated
      KubernetesDeploy::KubernetesResource::TIMEOUT_OVERRIDE_ANNOTATION_DEPRECATED
    else
      KubernetesDeploy::KubernetesResource::TIMEOUT_OVERRIDE_ANNOTATION
    end

    {
      "metadata" => {
        "name" => "customized",
        "annotations" => {
          timeout_override_annotation => value,
        },
      },
    }
  end

  def assert_includes_dummy_events(events, first:, second:)
    unless first || second
      assert_operator(events, :empty?)
      return
    end

    key = "DummyResource/test"
    expected = { key => [] }
    first_event = "FailedSync: Error syncing pod, skipping: failed to \"StartContainer\" for \"test\" with " \
      "ErrImagePull: \"rpc error: code = 2 desc = unknown blob\" (3 events)"
    expected[key] << first_event if first

    second_event = "FailedSync: Error syncing pod, skipping: failed to \"StartContainer\" for \"test\" with " \
      "CrashLoopBackOff: \"Back-off 1m20s restarting failed container=test pod=test-299526239-5vlj9_test" \
      "(00cfb839-4k2p-11e7-a12d-73972af001c2)\" (5 events)"
    expected[key] << second_event if second

    assert_equal(expected, events)
  end

  def dummy_events(start_time)
    [
      {
        kind: "DummyResource",
        name: "test",
        count: 3,
        last_seen: start_time + 3.seconds,
        reason: "FailedSync",
        message: <<~STRING,
          Error syncing pod, skipping: failed to \"StartContainer\" for \"test\" with ErrImagePull:
           \"rpc error: code = 2 desc = unknown blob\"
        STRING
      },
      {
        kind: "DummyResource",
        name: "test",
        count: 5,
        last_seen: start_time + 5.seconds,
        reason: "FailedSync",
        message: <<~STRING,
          Error syncing pod, skipping: failed to \"StartContainer\" for \"test\" with CrashLoopBackOff: \"Back-
          off 1m20s restarting failed container=test pod=test-299526239-5vlj9_test(00cfb839-4k2p-11e7-a12d-73972af001c2)\"
        STRING
      },
    ]
  end

  def build_event_jsonpath(dummy_events)
    event_separator = KubernetesDeploy::KubernetesResource::Event::EVENT_SEPARATOR
    field_separator = KubernetesDeploy::KubernetesResource::Event::FIELD_SEPARATOR
    dummy_events.each_with_object([]) do |e, jsonpaths|
      jsonpaths << [e[:kind], e[:name], e[:count], e[:last_seen].to_s, e[:reason], e[:message]].join(field_separator)
    end.join(event_separator)
  end

  def build_crd(name:, with_config: false)
    crd = {
      "kind" => "CustomResourceDefinition",
      "metadata" => {
        "name" => "#{name}s.test.io",
        "annotations" => {},
      },
      "spec" => {
        "names" => {
          "kind" => name.titleize,
        },
      },
    }
    if with_config
      crd["metadata"]["annotations"][KubernetesDeploy::CustomResourceDefinition::ROLLOUT_CONDITIONS_ANNOTATION] = "true"
    end
    crd
  end
end
