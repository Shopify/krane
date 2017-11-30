# frozen_string_literal: true
require 'test_helper'

class KubernetesResourceTest < KubernetesDeploy::TestCase
  class DummyResource < KubernetesDeploy::KubernetesResource
    def initialize(*)
      definition = { "kind" => "DummyResource", "metadata" => { "name" => "test" } }
      super(namespace: 'test', context: 'test', definition: definition, logger: @logger)
    end

    def exists?
      true
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

  private

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
