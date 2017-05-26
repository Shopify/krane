# frozen_string_literal: true
require 'test_helper'

require 'kubernetes-deploy/runner_task'
class RunnerTaskTest < KubernetesDeploy::IntegrationTest
  def test_run_works
    deploy_fixtures("hello-cloud", subset: ["template-runner.yml"])

    task_runner = build_task_runner
    assert task_runner.run(**valid_run_params)

    assert_logs_match(/Starting task runner/)
    pods = kubeclient.get_pods(namespace: @namespace)
    assert_equal 1, pods.length, "Expected 1 pod to exist, found #{pods.length}"
  end

  def test_run_bang_works
    deploy_fixtures("hello-cloud", subset: ["template-runner.yml"])

    task_runner = build_task_runner
    task_runner.run!(**valid_run_params)

    assert_logs_match(/Starting task runner/)
    pods = kubeclient.get_pods(namespace: @namespace)
    assert_equal 1, pods.length, "Expected 1 pod to exist, found #{pods.length}"
  end

  def test_run_substitutes_arguments
    deploy_fixtures("hello-cloud", subset: ["template-runner.yml"])

    task_runner = build_task_runner
    assert task_runner.run(
      task_template: 'hello-cloud-template-runner',
      entrypoint: nil,
      args: %w(rake some_task)
    )

    pods = kubeclient.get_pods(namespace: @namespace)
    assert_equal 1, pods.length, "Expected 1 pod to exist, found #{pods.length}"
    assert_equal %w(rake some_task), pods.first.spec.containers.first.args
  end

  def test_run_with_missing_namespace
    task_runner = build_task_runner(ns: "missing")
    refute task_runner.run(
      task_template: 'hello-cloud-template-runner',
      entrypoint: nil,
      args: 'a'
    )
    assert_logs_match("Configuration invalid: Namespace was not found")
  end

  def test_run_with_template_runner_template_missing
    task_runner = build_task_runner
    refute task_runner.run(**valid_run_params)
    expected = /Pod template `hello-cloud-template-runner` cannot be found in namespace: `.+`, context: `minikube`/
    assert_logs_match(expected)
  end

  def test_run_bang_with_template_missing_raises_exception
    task_runner = build_task_runner
    message = /Pod template `hello-cloud-template-runner` cannot be found in namespace: `.+`, context: `minikube`/
    assert_raises(KubernetesDeploy::RunnerTask::TaskTemplateMissingError, message: message) do
      task_runner.run!(**valid_run_params)
    end
  end

  private

  def valid_run_params
    { task_template: 'hello-cloud-template-runner', entrypoint: ['/bin/bash'], args: ["echo", "'KUBERNETES-DEPLOY'"] }
  end

  def build_task_runner(ns: @namespace)
    KubernetesDeploy::RunnerTask.new(context: KubeclientHelper::MINIKUBE_CONTEXT, namespace: ns, logger: logger)
  end
end
