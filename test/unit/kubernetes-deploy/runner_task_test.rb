# frozen_string_literal: true
require 'test_helper'

class RunnerTaskUnitTest < KubernetesDeploy::TestCase
  def test_missing_namespace
    assert_raises(KubernetesDeploy::RunnerTask::FatalTaskRunError,
      message: "Configuration invalid: Namespace was not found") do
      task_runner = KubernetesDeploy::RunnerTask.new(
        context: KubeclientHelper::MINIKUBE_CONTEXT,
        namespace: "missing",
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
        context: KubeclientHelper::MINIKUBE_CONTEXT
      )

      task_runner.run(
        task_template: nil,
        entrypoint: nil,
        args: ['a']
      )
    end
  end
end
