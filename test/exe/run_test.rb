# frozen_string_literal: true
require 'test_helper'
require 'krane/cli/krane'

class RunTest < KubernetesDeploy::TestCase
  def test_run_with_default_options
    set_krane_run_expectations
    krane_run!
  end

  def test_run_parses_global_timeout
    set_krane_run_expectations(new_args: { max_watch_seconds: 10 })
    krane_run!(flags: '--global-timeout 10s')
    set_krane_run_expectations(new_args: { max_watch_seconds: 60**2 })
    krane_run!(flags: '--global-timeout 1h')
  end

  def test_run_parses_verify_result
    set_krane_run_expectations(run_args: { verify_result: true })
    krane_run!(flags: '--verify-result true')
    set_krane_run_expectations(run_args: { verify_result: false })
    krane_run!(flags: '--no-verify-result')
  end

  def test_run_parses_command
    set_krane_run_expectations(run_args: { entrypoint: %w(/bin/sh) })
    krane_run!(flags: '--command /bin/sh')
  end

  def test_run_parses_arguments
    set_krane_run_expectations(run_args: { args: %w(hello) })
    krane_run!(flags: '--arguments hello')
  end

  def test_run_parses_template
    set_krane_run_expectations(run_args: { task_template: 'some-name' })
    krane_run!(flags: '--template some-name')
  end

  def test_run_parses_env_vars
    set_krane_run_expectations(run_args: { env_vars: %w(SOMETHING=8000 FOO=bar) })
    krane_run!(flags: '--env-vars SOMETHING=8000,FOO=bar')
  end

  def test_run_failure_with_not_enough_arguments_as_black_box
    out, err, status = krane_black_box('run', 'not_enough_arguments')
    assert_equal(1, status.exitstatus)
    assert_empty(out)
    assert_match("ERROR", err)
  end

  def test_run_failure_with_too_many_args
    out, err, status = krane_black_box('run', 'ns ctx some_extra_arg')
    assert_equal(1, status.exitstatus)
    assert_empty(out)
    assert_match("ERROR", err)
  end

  private

  def set_krane_run_expectations(new_args: {}, run_args: {})
    options = default_options(new_args, run_args)
    response = mock('RestartTask')
    response.expects(:run!).with(options[:run_args]).returns(true)
    KubernetesDeploy::RunnerTask.expects(:new).with(options[:new_args]).returns(response)
  end

  def krane_run!(flags: '')
    krane = Krane::CLI::Krane.new(
      [run_task_config.namespace, run_task_config.context],
      flags.split
    )
    krane.invoke("run_command")
  end

  def run_task_config
    @run_config ||= task_config(namespace: 'hello-cloud')
  end

  def default_options(new_args = {}, run_args = {})
    {
      new_args: {
        namespace: run_task_config.namespace,
        context: run_task_config.context,
        max_watch_seconds: 300,
      }.merge(new_args),
      run_args: {
        verify_result: true,
        task_template: 'task-runner-template',
        entrypoint: nil,
        args: nil,
        env_vars: [],
      }.merge(run_args),
    }
  end
end
