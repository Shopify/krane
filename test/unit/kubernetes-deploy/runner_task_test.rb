# frozen_string_literal: true
require 'test_helper'
require 'kubernetes-deploy/runner_task'

class RunnerTaskUnitTest < KubernetesDeploy::TestCase
  def setup
    Kubeclient::Client.any_instance.stubs(:discover)
    super
  end

  def test_run_with_invalid_configuration
    task_runner = KubernetesDeploy::RunnerTask.new(
      context: KubeclientHelper::MINIKUBE_CONTEXT,
      namespace: nil,
      logger: logger,
    )

    refute task_runner.run(task_template: nil, entrypoint: nil, args: nil)
    assert_logs_match(/task template name can't be nil/)
    assert_logs_match(/namespace can't be empty/)
    assert_logs_match(/args can't be nil/)
  end

  def test_run_bang_with_invalid_configuration
    task_runner = KubernetesDeploy::RunnerTask.new(
      context: KubeclientHelper::MINIKUBE_CONTEXT,
      namespace: nil,
      logger: logger,
    )

    err = assert_raises(KubernetesDeploy::RunnerTask::FatalTaskRunError) do
      task_runner.run!(task_template: nil, entrypoint: nil, args: nil)
    end

    assert_match(/Task template name can't be nil/, err.to_s)
    assert_match(/Namespace can't be empty/, err.to_s)
    assert_match(/Args can't be nil/, err.to_s)
  end
end
