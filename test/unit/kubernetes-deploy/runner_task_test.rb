# frozen_string_literal: true
require 'test_helper'
require 'kubernetes-deploy/runner_task'

class RunnerTaskUnitTest < KubernetesDeploy::TestCase
  def test_run_with_invalid_configuration
    task_runner = KubernetesDeploy::RunnerTask.new(
      context: KubeclientHelper::TEST_CONTEXT,
      namespace: nil,
      logger: logger,
    )

    refute(task_runner.run(task_template: nil, entrypoint: nil, args: nil))
    assert_logs_match(/Task template name can't be nil/)
    assert_logs_match(/Namespace can't be empty/)
    assert_logs_match(/Args can't be nil/)
  end

  def test_run_bang_with_invalid_configuration
    task_runner = KubernetesDeploy::RunnerTask.new(
      context: KubeclientHelper::TEST_CONTEXT,
      namespace: nil,
      logger: logger,
    )

    err = assert_raises(KubernetesDeploy::FatalDeploymentError) do
      task_runner.run!(task_template: nil, entrypoint: nil, args: nil)
    end

    assert_match(/Task template name can't be nil/, err.to_s)
    assert_match(/Namespace can't be empty/, err.to_s)
    assert_match(/Args can't be nil/, err.to_s)
  end
end
