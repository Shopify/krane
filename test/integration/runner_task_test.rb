# frozen_string_literal: true
require 'test_helper'

require 'kubernetes-deploy/runner_task'
class RunnerTaskTest < KubernetesDeploy::IntegrationTest
  def test_works
    deploy_fixtures("hello-cloud", subset: ["template-runner.yml"])

    task_runner = KubernetesDeploy::RunnerTask.new(
      context: KubeclientHelper::MINIKUBE_CONTEXT,
      namespace: @namespace,
      logger: logger,
    )

    assert task_runner.run(
      task_template: 'hello-cloud-template-runner',
      entrypoint: ['/bin/bash'],
      args: ["echo", "'KUBERNETES-DEPLOY'"]
    )

    assert_logs_match(/Starting task runner/)
    pods = kubeclient.get_pods(namespace: @namespace)
    assert_equal 1, pods.length, "Expected 1 pod to exist, found #{pods.length}"
  end

  def test_substitutes_arguments
    deploy_fixtures("hello-cloud", subset: ["template-runner.yml"])

    task_runner = KubernetesDeploy::RunnerTask.new(
      context: KubeclientHelper::MINIKUBE_CONTEXT,
      namespace: @namespace,
      logger: logger,
    )

    assert task_runner.run(
      task_template: 'hello-cloud-template-runner',
      entrypoint: nil,
      args: %w(rake some_task)
    )

    pods = kubeclient.get_pods(namespace: @namespace)
    assert_equal 1, pods.length, "Expected 1 pod to exist, found #{pods.length}"
    assert_equal %w(rake some_task), pods.first.spec.containers.first.args
  end

  def test_missing_namespace
    task_runner = KubernetesDeploy::RunnerTask.new(
      context: KubeclientHelper::MINIKUBE_CONTEXT,
      namespace: "missing",
      logger: logger,
    )

    refute task_runner.run(
      task_template: 'hello-cloud-template-runner',
      entrypoint: nil,
      args: 'a'
    )
    assert_logs_match("Configuration invalid: Namespace was not found")
  end

  def test_template_runner_template_missing
    task_runner = KubernetesDeploy::RunnerTask.new(
      context: KubeclientHelper::MINIKUBE_CONTEXT,
      namespace: @namespace,
      logger: logger,
    )

    refute task_runner.run(
      task_template: 'hello-cloud-template-runner',
      entrypoint: ['/bin/bash'],
      args: ["echo", "'KUBERNETES-DEPLOY'"]
    )
    expected = /Pod template `hello-cloud-template-runner` cannot be found in namespace: `.+`, context: `minikube`/
    assert_logs_match(expected)
  end
end
