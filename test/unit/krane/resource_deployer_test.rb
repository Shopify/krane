# frozen_string_literal: true
require 'test_helper'
require 'krane/resource_deployer'

class ResourceDeployerTest < Krane::TestCase
  def test_deploy_prune_builds_whitelist
    whitelist_kind = "fake_kind"
    resource = build_mock_resource
    Krane::Kubectl.any_instance.expects(:run).with do |*args|
      args.include?("--prune-whitelist=#{whitelist_kind}")
    end.returns(["", "", stub(success?: true)])
    resource_deployer(kubectl_times: 0, prune_whitelist: [whitelist_kind]).deploy!([resource], false, true)
  end

  def test_deploy_no_prune_doesnt_prune
    whitelist_kind = "fake_kind"
    resource = build_mock_resource
    Krane::Kubectl.any_instance.expects(:run).with do |*args|
      !args.include?("--prune-whitelist=#{whitelist_kind}")
    end.returns(["", "", stub(success?: true)])
    resource_deployer(kubectl_times: 0, prune_whitelist: [whitelist_kind]).deploy!([resource], false, false)
  end

  def test_deploy_verify_false_message
    resource = build_mock_resource
    resource_deployer.deploy!([resource], false, false)
    logger.print_summary(:done) # Force logger to flush
    assert_logs_match_all(["Deploy result verification is disabled for this deploy."])
  end

  def test_deploy_time_out_error
    resource = build_mock_resource(final_status: "timeout")
    watcher = mock("ResourceWatcher")
    watcher.expects(:run).returns(true)
    Krane::ResourceWatcher.expects(:new).returns(watcher)
    assert_raises(Krane::DeploymentTimeoutError) do
      resource_deployer.deploy!([resource], true, false)
    end
  end

  def test_deploy_verify_false_no_timeout
    resource = build_mock_resource(final_status: "timeout")
    resource_deployer.deploy!([resource], false, false)
    logger.print_summary(:done) # Force logger to flush
    assert_logs_match_all(["Deploy result verification is disabled for this deploy."])
  end

  def test_deploy_failure_error
    resource = build_mock_resource(final_status: "failure")
    watcher = mock("ResourceWatcher")
    watcher.expects(:run)
    Krane::ResourceWatcher.expects(:new).returns(watcher)
    assert_raises(Krane::FatalDeploymentError) do
      resource_deployer.deploy!([resource], true, false)
    end
  end

  def test_deploy_verify_false_no_failure_error
    resource = build_mock_resource(final_status: "failure")
    resource_deployer.deploy!([resource], false, false)
    logger.print_summary(:done) # Force logger to flush
    assert_logs_match_all(["Deploy result verification is disabled for this deploy."])
  end

  def test_predeploy_priority_resources_respects_pre_deploy_list
    kind = "MockResource"
    resource = build_mock_resource
    watcher = mock("ResourceWatcher")
    watcher.expects(:run).returns(true)
    # ResourceDeployer only creates a ResourceWatcher if one or more resources
    # are deployed. See test_predeploy_priority_resources_respects_empty_pre_deploy_list
    # for counter example
    Krane::ResourceWatcher.expects(:new).returns(watcher)
    priority_list = { kind => { groups: ["core"], skip_groups: [] } }
    resource_deployer.predeploy_priority_resources([resource], priority_list)
  end

  def test_predeploy_priority_resources_respects_empty_pre_deploy_list
    resource = build_mock_resource
    priority_list = []
    Krane::ResourceWatcher.expects(:new).times(0)
    resource_deployer(kubectl_times: 0).predeploy_priority_resources([resource], priority_list)
  end

  private

  def resource_deployer(kubectl_times: 1, prune_whitelist: [])
    unless kubectl_times == 0
      runless = build_runless_kubectl
      Krane::Kubectl.expects(:new).returns(runless).times(kubectl_times)
    end
    @deployer = Krane::ResourceDeployer.new(current_sha: 'test-sha',
      statsd_tags: [], task_config: task_config, prune_whitelist: prune_whitelist,
      global_timeout: 1, selector: nil)
  end

  def build_mock_resource(final_status: "success", hits_to_complete: 0, name: "web-pod")
    MockResource.new(name, hits_to_complete, final_status)
  end
end
