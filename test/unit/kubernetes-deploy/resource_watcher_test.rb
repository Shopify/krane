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

  def test_success_with_mock_resource
    resource = build_mock_resource

    watcher = KubernetesDeploy::ResourceWatcher.new([resource], logger: logger)
    watcher.run(delay_sync: 0.1)

    assert_logs_match(/Waiting for web-pod with 1s timeout/)
    assert_logs_match(/Spent (\S+)s waiting for web-pod/)
  end

  def test_failure_with_mock_resource
    resource = build_mock_resource(final_status: "failed")

    watcher = KubernetesDeploy::ResourceWatcher.new([resource], logger: logger)
    watcher.run(delay_sync: 0.1)

    assert_logs_match(/Waiting for web-pod with 1s timeout/)
    assert_logs_match(/web-pod failed to deploy with status 'failed'/)
    assert_logs_match(/Spent (\S+)s waiting for web-pod/)
  end

  def test_timeout_from_resource
    resource = build_mock_resource(final_status: "timeout")

    watcher = KubernetesDeploy::ResourceWatcher.new([resource], logger: logger)
    watcher.run(delay_sync: 0.1)

    assert_logs_match(/Waiting for web-pod with 1s timeout/)
    assert_logs_match(/web-pod failed to deploy with status 'timeout'/)
    assert_logs_match(/Spent (\S+)s waiting for web-pod/)
  end

  def test_wait_logging_when_resources_do_not_finish_together
    first = build_mock_resource(final_status: "success", hits_to_complete: 1, name: "first")
    second = build_mock_resource(final_status: "timeout", hits_to_complete: 2, name: "second")
    third = build_mock_resource(final_status: "failed", hits_to_complete: 3, name: "third")
    fourth = build_mock_resource(final_status: "success", hits_to_complete: 4, name: "fourth")

    watcher = KubernetesDeploy::ResourceWatcher.new([first, second, third, fourth], logger: logger)
    watcher.run(delay_sync: 0.1)

    assert_logs_match(/Waiting for first, second, third, fourth with 4s timeout/)
    assert_logs_match(/second failed to deploy with status 'timeout'/)
    assert_logs_match(/third failed to deploy with status 'failed'/)
    assert_logs_match(/Spent (\S+)s waiting for first, second, third, fourth/)
  end

  private

  MockResource = Struct.new(:id, :hits_to_complete, :status) do
    def sync
      @hits ||= 0
      @hits += 1
    end

    def deploy_finished?
      deploy_succeeded? || deploy_failed? || deploy_timed_out?
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

    private

    def hits_complete?
      @hits >= hits_to_complete
    end
  end

  def build_mock_resource(final_status: "success", hits_to_complete: 1, name: "web-pod")
    MockResource.new(name, hits_to_complete, final_status)
  end
end
