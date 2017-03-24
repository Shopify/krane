# frozen_string_literal: true
require 'test_helper'

class ResourceWatcherTest < KubernetesDeploy::TestCase
  def test_requires_enumerable
    err = assert_raises(ArgumentError) do
      KubernetesDeploy::ResourceWatcher.new(Object.new)
    end
    assert_equal "ResourceWatcher expects Enumerable collection, got `Object` instead", err.to_s

    KubernetesDeploy::ResourceWatcher.new([])
  end

  def test_success_with_mock_resource
    resource = build_mock_resource

    watcher = KubernetesDeploy::ResourceWatcher.new([resource])
    watcher.run(delay_sync: 0.1)

    assert_logs_match(/Waiting for web-pod with 1s timeout/)
    assert_logs_match(/Spent (\S+)s waiting for web-pod/)
  end

  def test_failure_with_mock_resource
    resource = build_mock_resource("failed")

    watcher = KubernetesDeploy::ResourceWatcher.new([resource])
    watcher.run(delay_sync: 0.1)

    assert_logs_match(/Waiting for web-pod with 1s timeout/)
    assert_logs_match(/web-pod failed to deploy with status 'failed'/)
    assert_logs_match(/Spent (\S+)s waiting for web-pod/)
  end

  def test_timeout_from_resource
    resource = build_mock_resource("timeout")

    watcher = KubernetesDeploy::ResourceWatcher.new([resource])
    watcher.run(delay_sync: 0.1)

    assert_logs_match(/Waiting for web-pod with 1s timeout/)
    assert_logs_match(/web-pod failed to deploy with status 'timeout'/)
    assert_logs_match(/Spent (\S+)s waiting for web-pod/)
  end

  private

  MockResource = Struct.new(:id, :timeout, :status) do
    def sync
      @hits ||= 0
      @hits += 1
    end

    def deploy_finished?
      @hits > 3
    end

    def deploy_failed?
      status == "failed"
    end

    def deploy_timed_out?
      status == "timeout"
    end
  end

  def build_mock_resource(status = nil)
    MockResource.new("web-pod", 1, status)
  end
end
