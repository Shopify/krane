# frozen_string_literal: true
require 'test_helper'
require 'kubernetes-deploy/runner_task'

class RunnerTaskUnitTest < KubernetesDeploy::TestCase
  def test_missing_namespace
    assert_raises(KubernetesDeploy::RunnerTask::FatalTaskRunError,
      message: "Configuration invalid: Namespace was not found") do
      task_runner = KubernetesDeploy::RunnerTask.new(
        context: KubeclientHelper::MINIKUBE_CONTEXT,
        namespace: "missing",
        logger: test_logger,
      )

      task_runner.run(
        task_template: 'hello-cloud-template-runner',
        entrypoint: nil,
        args: 'a'
      )
    end
  end

  def test_missing_arguments
    assert_raises(KubernetesDeploy::RunnerTask::FatalTaskRunError) do
      task_runner = KubernetesDeploy::RunnerTask.new(
        context: KubeclientHelper::MINIKUBE_CONTEXT,
        namespace: @namespace,
        logger: test_logger,
      )

      task_runner.run(
        task_template: 'hello-cloud-template-runner',
        entrypoint: nil,
        args: nil
      )
    end
  end

  def test_missing_template
    assert_raises(KubernetesDeploy::RunnerTask::FatalTaskRunError) do
      task_runner = KubernetesDeploy::RunnerTask.new(
        namespace: @namespace,
        context: KubeclientHelper::MINIKUBE_CONTEXT,
        logger: test_logger,
      )

      task_runner.run(
        task_template: nil,
        entrypoint: nil,
        args: ['a']
      )
    end
  end
end
