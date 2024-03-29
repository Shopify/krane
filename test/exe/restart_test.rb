# frozen_string_literal: true
require 'test_helper'
require 'krane/cli/krane'

class RestartTest < Krane::TestCase
  def test_restart_with_default_options
    set_krane_restart_expectations
    krane_restart!
  end

  def test_restart_parses_global_timeout
    set_krane_restart_expectations(new_args: { global_timeout: 10 })
    krane_restart!(flags: '--global-timeout 10s')
    set_krane_restart_expectations(new_args: { global_timeout: 60**2 })
    krane_restart!(flags: '--global-timeout 1h')
  end

  def test_restart_passes_deployments_transparently
    set_krane_restart_expectations(run_args: { deployments: ['web'] })
    krane_restart!(flags: '--deployments web')
    set_krane_restart_expectations(run_args: { deployments: ['web', 'jobs'] })
    krane_restart!(flags: '--deployments web jobs')
  end

  def test_restart_passes_statefulsets_transparently
    set_krane_restart_expectations(run_args: { statefulsets: ['ss'] })
    krane_restart!(flags: '--statefulsets ss')
    set_krane_restart_expectations(run_args: { statefulsets: ['ss', 'ss-2'] })
    krane_restart!(flags: '--statefulsets ss ss-2')
  end

  def test_restart_passes_daemonsets_transparently
    set_krane_restart_expectations(run_args: { daemonsets: ['ds'] })
    krane_restart!(flags: '--daemonsets ds')
    set_krane_restart_expectations(run_args: { daemonsets: ['ds', 'ds-2'] })
    krane_restart!(flags: '--daemonsets ds ds-2')
  end

  def test_restart_passes_multiple_workload_types_transparently
    set_krane_restart_expectations(
      run_args: { deployments: ['web', 'jobs'], statefulsets: ['ss', 'ss-2'], daemonsets: ['ds', 'ds-2'] }
    )
    krane_restart!(flags: '--deployments web jobs --statefulsets ss ss-2 --daemonsets ds ds-2')
  end

  def test_restart_parses_selector
    options = default_options
    response = mock('RestartTask')
    response.expects(:run!).returns(true).with(has_entries(selector: is_a(Krane::LabelSelector), verify_result: true))
    Krane::RestartTask.expects(:new).with(options[:new_args]).returns(response)

    krane_restart!(flags: '--selector name:web')
  end

  def test_restart_passes_verify_result
    set_krane_restart_expectations(run_args: { verify_result: true })
    krane_restart!(flags: '--verify-result true')
    set_krane_restart_expectations(run_args: { verify_result: false })
    krane_restart!(flags: '--verify-result false')
  end

  def test_restart_failure_as_black_box
    out, err, status = krane_black_box("restart", "-q")
    assert_equal(status.exitstatus, 1)
    assert_empty(out)
    assert_match("ERROR", err)
  end

  private

  def set_krane_restart_expectations(new_args: {}, run_args: {})
    options = default_options(new_args, run_args)
    response = mock('RestartTask')
    response.expects(:run!).with(options[:run_args]).returns(true)
    Krane::RestartTask.expects(:new).with(options[:new_args]).returns(response)
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

  def default_options(new_args = {}, run_args = {})
    {
      new_args: {
        namespace: restart_task_config.namespace,
        context: restart_task_config.context,
        global_timeout: 300,
      }.merge(new_args),
      run_args: {
        deployments: [],
        statefulsets: [],
        daemonsets: [],
        selector: nil,
        verify_result: true,
      }.merge(run_args),
    }
  end
end
