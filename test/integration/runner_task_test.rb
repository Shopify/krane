# frozen_string_literal: true
require 'test_helper'

require 'kubernetes-deploy/runner_task'
class RunnerTaskTest < KubernetesDeploy::IntegrationTest
  def test_works
    deploy_fixtures("hello-cloud", subset: ["template-runner.yml"])

    task_runner = KubernetesDeploy::RunnerTask.new(
      context: KubeclientHelper::MINIKUBE_CONTEXT,
      namespace: @namespace,
    )

    task_runner.run(
      task_template: 'hello-cloud-template-runner',
      entrypoint: ['/bin/bash'],
      args: %w(echo "KUBERNETES-DEPLOY")
    )

    assert_logs_match(/Starting task runner/)
  end

  def test_substitutes_arguments
    deploy_fixtures("hello-cloud", subset: ["template-runner.yml"])

    task_runner = KubernetesDeploy::RunnerTask.new(
      context: KubeclientHelper::MINIKUBE_CONTEXT,
      namespace: @namespace,
    )

    pod = task_runner.run(
      task_template: 'hello-cloud-template-runner',
      entrypoint: nil,
      args: %w(rake some_task)
    )

    assert_equal %w(rake some_task), pod.spec.containers.first.args
  end
end
