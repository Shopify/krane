# frozen_string_literal: true
require 'test_helper'
require 'krane/cli/krane'

class RestartTest < KubernetesDeploy::TestCase
  def test_restart_with_default_options
    set_krane_restart_expecations
    krane_restart!
  end

  def test_restart_parses_global_timeout
    set_krane_restart_expecations(new_args: { max_watch_seconds: 10 })
    krane_restart!(flags: '--global-timeout 10s')
    set_krane_restart_expecations(new_args: { max_watch_seconds: 60**2 })
    krane_restart!(flags: '--global-timeout 1h')
  end

  def test_restart_passes_deployments_transparently
    set_krane_restart_expecations(deployments: ['web'])
    krane_restart!(flags: '--deployments web')
    set_krane_restart_expecations(deployments: ['web', 'jobs'])
    krane_restart!(flags: '--deployments web jobs')
  end

  def test_restart_parses_selector
    options = default_options
    response = mock('RestartTask')
    response.expects(:run!).returns(true).with(options[:deployments],
      has_entries(selector: is_a(KubernetesDeploy::LabelSelector), verify_result: true))
    KubernetesDeploy::RestartTask.expects(:new).with(options[:new_args]).returns(response)

    krane_restart!(flags: '--selector name:web')
  end

  def test_restart_passes_verify_result
    set_krane_restart_expecations(run_args: { verify_result: true })
    krane_restart!(flags: '--verify-result true')
    set_krane_restart_expecations(run_args: { verify_result: false })
    krane_restart!(flags: '--verify-result false')
  end

  def test_restart_failure_as_black_box
    out, err, status = krane_black_box("restart", "-q")
    assert_equal(status.exitstatus, 1)
    assert_empty(out)
    assert_match("ERROR", err)
  end

  private

  def set_krane_restart_expecations(new_args: {}, deployments: nil, run_args: {})
    options = default_options(new_args, deployments, run_args)
    response = mock('RestartTask')
    response.expects(:run!).with(options[:deployments], options[:run_args]).returns(true)
    KubernetesDeploy::RestartTask.expects(:new).with(options[:new_args]).returns(response)
  end

  def krane_restart!(flags: '')
    krane = Krane::CLI::Krane.new(
      [restart_task_config.namespace, restart_task_config.context],
      flags.split
    )
    krane.invoke("restart")
  end

  def restart_task_config
    @restart_config ||= task_config(namespace: 'test-namespace')
  end

  def default_options(new_args = {}, deployments = nil, run_args = {})
    {
      new_args: {
        namespace: restart_task_config.namespace,
        context: restart_task_config.context,
        max_watch_seconds: 300,
      }.merge(new_args),
      deployments: deployments,
      run_args: {
        selector: nil,
        verify_result: true,
      }.merge(run_args),
    }
  end
end
