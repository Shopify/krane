# frozen_string_literal: true
require 'test_helper'

class KubernetesResourceTest < KubernetesDeploy::TestCase
  class DummyResource < KubernetesDeploy::KubernetesResource
    def initialize(definition_extras: {})
      definition = { "kind" => "DummyResource", "metadata" => { "name" => "test" } }.merge(definition_extras)
      super(namespace: 'test', context: 'test', definition: definition, logger: @logger)
    end

    def exists?
      true
    end

    def file_path
      "/tmp/foo/bar"
    end
  end

  def test_service_and_deployment_timeouts_are_equal
    message = "Service and Deployment timeouts have to match since services are waiting to get endpoints " \
      "from their backing deployments"
    assert_equal KubernetesDeploy::Service.timeout, KubernetesDeploy::Deployment.timeout, message
  end

  def test_fetch_events_parses_tricky_events_correctly
    start_time = Time.now.utc - 10.seconds
    dummy = DummyResource.new
    dummy.deploy_started_at = start_time

    tricky_events = dummy_events(start_time)
    assert tricky_events.first[:message].count("\n") > 1, "Sanity check failed: inadequate newlines in test events"

    stub_kubectl_response("get", "events", anything, resp: build_event_jsonpath(tricky_events), json: false)
    events = dummy.fetch_events
    assert_includes_dummy_events(events, first: true, second: true)
  end

  def test_fetch_events_excludes_events_from_previous_deploys
    start_time = Time.now.utc - 10.seconds
    dummy = DummyResource.new
    dummy.deploy_started_at = start_time
    mixed_time_events = dummy_events(start_time)
    mixed_time_events.first[:last_seen] = 1.hour.ago

    stub_kubectl_response("get", "events", anything, resp: build_event_jsonpath(mixed_time_events), json: false)
    events = dummy.fetch_events
    assert_includes_dummy_events(events, first: false, second: true)
  end

  def test_fetch_events_returns_empty_hash_when_kubectl_results_empty
    dummy = DummyResource.new
    dummy.deploy_started_at = Time.now.utc - 10.seconds

    stub_kubectl_response("get", "events", anything, resp: "", json: false)
    events = dummy.fetch_events
    assert_operator events, :empty?
  end

  def test_can_override_hardcoded_timeout_via_an_annotation
    basic_resource = DummyResource.new
    assert_equal 5.minutes, basic_resource.timeout

    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata("60"))
    assert_equal 60, customized_resource.timeout

    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata(" 60  "))
    assert_equal 60, customized_resource.timeout
  end

  def test_blank_timeout_annotation_is_ignored
    stub_kubectl_response("create", "-f", "/tmp/foo/bar", "--dry-run", "--output=name", anything, resp: "{}")

    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata(""))
    customized_resource.validate_definition
    refute customized_resource.validation_failed?, "Blank annotation with was invalid"
    assert_equal 5.minutes, customized_resource.timeout
  end

  def test_validation_of_timeout_annotation
    expected_cmd = ["create", "-f", "/tmp/foo/bar", "--dry-run", "--output=name", anything]
    error_msg = "kubernetes-deploy.shopify.io/timeout-override-seconds annotation " \
      "must contain digits only and must be > 0"

    stub_kubectl_response(*expected_cmd, resp: "{}")
    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata("sixty"))
    customized_resource.validate_definition
    assert customized_resource.validation_failed?, "Annotation with 'sixty' was valid"
    assert_equal error_msg, customized_resource.validation_error_msg

    stub_kubectl_response(*expected_cmd, resp: "{}")
    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata("-1"))
    customized_resource.validate_definition
    assert customized_resource.validation_failed?, "Annotation with '-1' was valid"
    assert_equal error_msg, customized_resource.validation_error_msg

    stub_kubectl_response(*expected_cmd, resp: "{}")
    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata("0"))
    customized_resource.validate_definition
    assert customized_resource.validation_failed?, "Annotation with '0' was valid"
    assert_equal error_msg, customized_resource.validation_error_msg

    stub_kubectl_response(*expected_cmd, resp: "{}")
    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata("10m"))
    customized_resource.validate_definition
    assert customized_resource.validation_failed?, "Annotation with '10m' was valid"
    assert_equal error_msg, customized_resource.validation_error_msg
  end

  def test_annotation_and_kubectl_error_messages_are_combined
    stub_kubectl_response(
      "create", "-f", "/tmp/foo/bar", "--dry-run", "--output=name", anything,
      resp: "{}",
      err: "Error from kubectl: Something else in this template was not valid",
      success: false
    )

    customized_resource = DummyResource.new(definition_extras: build_timeout_metadata("bad"))
    customized_resource.validate_definition
    assert customized_resource.validation_failed?, "Expected resource to be invalid"

    expected = <<~STRING.strip
      kubernetes-deploy.shopify.io/timeout-override-seconds annotation must contain digits only and must be > 0
      Error from kubectl: Something else in this template was not valid
    STRING
    assert_equal expected, customized_resource.validation_error_msg
  end

  private

  def build_timeout_metadata(value)
    {
      "metadata" => {
        "name" => "customized",
        "annotations" => {
          KubernetesDeploy::KubernetesResource::TIMEOUT_OVERRIDE_ANNOTATION => value
        }
      }
    }
  end

  def assert_includes_dummy_events(events, first:, second:)
    unless first || second
      assert_operator events, :empty?
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

    assert_equal expected, events
  end

  def dummy_events(start_time)
    [
      {
        kind: "DummyResource",
        name: "test",
        count: 3,
        last_seen: start_time + 3.seconds,
        reason: "FailedSync",
        message: <<~STRING
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
        message: <<~STRING
          Error syncing pod, skipping: failed to \"StartContainer\" for \"test\" with CrashLoopBackOff: \"Back-
          off 1m20s restarting failed container=test pod=test-299526239-5vlj9_test(00cfb839-4k2p-11e7-a12d-73972af001c2)\"
        STRING
      }
    ]
  end

  def build_event_jsonpath(dummy_events)
    event_separator = KubernetesDeploy::KubernetesResource::Event::EVENT_SEPARATOR
    field_separator = KubernetesDeploy::KubernetesResource::Event::FIELD_SEPARATOR
    dummy_events.each_with_object([]) do |e, jsonpaths|
      jsonpaths << [e[:kind], e[:name], e[:count], e[:last_seen].to_s, e[:reason], e[:message]].join(field_separator)
    end.join(event_separator)
  end
end
