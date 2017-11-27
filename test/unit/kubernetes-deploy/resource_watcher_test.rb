# frozen_string_literal: true
require 'test_helper'

class ResourceWatcherTest < KubernetesDeploy::TestCase
  def test_requires_enumerable
    expected_msg = "ResourceWatcher expects Enumerable collection, got `Object` instead"
    assert_raises_message(ArgumentError, expected_msg) do
      KubernetesDeploy::ResourceWatcher.new(Object.new, logger: logger)
    end

    KubernetesDeploy::ResourceWatcher.new([], logger: logger)
  end

  def test_success_with_mock_resource_and_summary_recording_enabled
    resource = build_mock_resource

    watcher = KubernetesDeploy::ResourceWatcher.new([resource], logger: logger)
    watcher.run(delay_sync: 0.1)
    logger.print_summary(true)

    assert_logs_match_all([
      /Successfully deployed in \d.\ds: web-pod/,
      "Successfully deployed 1 resource",
      /web-pod\s+success \(1 hits\)/
    ], in_order: true)
  end

  def test_success_with_mock_resource_and_summary_recording_disabled
    resource = build_mock_resource

    watcher = KubernetesDeploy::ResourceWatcher.new([resource], logger: logger)
    watcher.run(delay_sync: 0.1, record_summary: false)
    logger.print_summary(true)

    assert_logs_match(/Successfully deployed in \d.\ds: web-pod/)
    refute_logs_match("Successfully deployed 1 resource")
    refute_logs_match(/web-pod.*success/)
  end

  def test_failure_with_mock_resource
    resource = build_mock_resource(final_status: "failed")

    watcher = KubernetesDeploy::ResourceWatcher.new([resource], logger: logger)
    watcher.run(delay_sync: 0.1)

    assert_logs_match(/web-pod failed to deploy after \d\.\ds/)
  end

  def test_timeout_from_resource
    resource = build_mock_resource(final_status: "timeout")

    watcher = KubernetesDeploy::ResourceWatcher.new([resource], logger: logger)
    watcher.run(delay_sync: 0.1)

    assert_logs_match(/web-pod rollout timed out/)
  end

  def test_wait_logging_when_resources_do_not_finish_together
    first = build_mock_resource(final_status: "success", hits_to_complete: 1, name: "first")
    second = build_mock_resource(final_status: "timeout", hits_to_complete: 2, name: "second")
    third = build_mock_resource(final_status: "failed", hits_to_complete: 3, name: "third")
    fourth = build_mock_resource(final_status: "success", hits_to_complete: 4, name: "fourth")

    watcher = KubernetesDeploy::ResourceWatcher.new([first, second, third, fourth], logger: logger)
    watcher.run(delay_sync: 0.1)

    assert_logs_match_all([
      /Successfully deployed in \d.\ds: first/,
      /Continuing to wait for: second, third, fourth/,
      /second rollout timed out/,
      /Continuing to wait for: third, fourth/,
      /third failed to deploy after \d.\ds/,
      /Continuing to wait for: fourth/,
      /Successfully deployed in \d.\ds: fourth/
    ], in_order: true)
  end

  def test_reminder_logged_at_interval_even_when_nothing_happened
    resource1 = build_mock_resource(final_status: "success", hits_to_complete: 1, name: 'first')
    resource2 = build_mock_resource(final_status: "success", hits_to_complete: 9, name: 'second')
    resource3 = build_mock_resource(final_status: "success", hits_to_complete: 9, name: 'third')
    watcher = KubernetesDeploy::ResourceWatcher.new([resource1, resource2, resource3], logger: logger)
    watcher.run(delay_sync: 0.1, reminder_interval: 0.5.seconds)

    assert_logs_match_all([
      /Successfully deployed in \d.\ds: first/,
      /Continuing to wait for: second, third/,
      /Still waiting for: second, third/,
      /Successfully deployed in \d.\ds: second, third/
    ], in_order: true)
    assert_logs_match(/Continuing to wait for: second, third/, 1) # only once
  end

  private

  MockResource = Struct.new(:id, :hits_to_complete, :status) do
    def sync
      @hits ||= 0
      @hits += 1
    end

    def deploy_succeeded?
      status == "success" && hits_complete?
    end

    def deploy_failed?
      status == "failed" && hits_complete?
    end

    def deploy_timed_out?
      status == "timeout" && hits_complete?
    end

    def timeout
      hits_to_complete
    end

    def debug_message
      "Something went wrong"
    end

    def pretty_status
      "#{id}  #{status} (#{@hits} hits)"
    end

    def report_status_to_statsd(watch_time)
    end

    private

    def hits_complete?
      @hits >= hits_to_complete
    end
  end

  def build_mock_resource(final_status: "success", hits_to_complete: 1, name: "web-pod")
    MockResource.new(name, hits_to_complete, final_status)
  end
end
