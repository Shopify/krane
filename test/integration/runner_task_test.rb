# frozen_string_literal: true
require 'test_helper'

require 'kubernetes-deploy/runner_task'
class RunnerTaskTest < KubernetesDeploy::IntegrationTest
  def test_run_works
    deploy_fixtures("hello-cloud", subset: ["template-runner.yml", "configmap-data.yml"])

    task_runner = build_task_runner
    assert task_runner.run(**valid_run_params)

    assert_logs_match(/Starting task runner/)
    pods = kubeclient.get_pods(namespace: @namespace)
    assert_equal 1, pods.length, "Expected 1 pod to exist, found #{pods.length}"
  end

  def test_run_global_timeout_with_max_watch_seconds
    deploy_fixtures("hello-cloud", subset: ["template-runner.yml", "configmap-data.yml"])

    task_runner = build_task_runner(max_watch_seconds: 5)
    refute task_runner.run(**valid_run_params.merge(verify_result: true, args: ['sleep 20']))

    assert_logs_match_all([
      /Starting task runner pod: 'task-runner-\w+'/,
      "Result: TIMED OUT",
      "Timed out waiting for 1 resource to deploy",
      %r{Pod/task-runner-\w+: GLOBAL WATCH TIMEOUT \(5 seconds\)}
    ])
  end

  def test_run_bad_args
    deploy_fixtures("hello-cloud", subset: ["template-runner.yml", "configmap-data.yml"])

    task_runner = build_task_runner
    refute task_runner.run(**valid_run_params.merge(verify_result: true, args: %w(FAKE)))

    assert_logs_match_all([
      /Starting task runner pod: 'task-runner-\w+'/,
      "Result: FAILURE",
      "Failed to deploy 1 resource",
      %r{Pod/task-runner-\w+: FAILED},
      "/bin/sh: FAKE: not found"
    ])
  end

  def test_run_with_verify_result
    deploy_fixtures("hello-cloud", subset: ["template-runner.yml", "configmap-data.yml"])

    task_runner = build_task_runner
    assert task_runner.run(**valid_run_params.merge(verify_result: true,
      args: ['echo "start" && sleep 6 && echo "finish"']))

    assert_logs_match_all([
      /Starting task runner pod: 'task-runner-\w+'/,
      "start", # From pod logs
      "finish",
      "Result: SUCCESS",
      "Successfully deployed 1 resource",
    ])
    pods = kubeclient.get_pods(namespace: @namespace)
    assert_equal 1, pods.length, "Expected 1 pod to exist, found #{pods.length}"
  end

  def test_run_doesnt_miss_logs_across_pollings
    deploy_fixtures("hello-cloud", subset: ["template-runner.yml", "configmap-data.yml"])
    upper = 3_000
    task_runner = build_task_runner
    assert task_runner.run(**valid_run_params.merge(verify_result: true,
      args: ["i=0; while [ $i -lt #{upper} ]; do echo \"$i\"; sleep 0.001; i=$((i+1)); done"]))

    assert_logs_match_all(
      [/Starting task runner pod: 'task-runner-\w+'/] +
      (1...upper).map(&:to_s) +
      ["Result: SUCCESS", "Successfully deployed 1 resource"],
      in_order: true
    )
    pods = kubeclient.get_pods(namespace: @namespace)
    assert_equal 1, pods.length, "Expected 1 pod to exist, found #{pods.length}"
  end

  def test_run_with_bad_restart_policy
    deploy_fixtures("hello-cloud", subset: ["template-runner.yml", "configmap-data.yml"]) do |f|
      f["template-runner.yml"]["PodTemplate"].first["template"]["spec"]["restartPolicy"] = "OnFailure"
    end

    task_runner = build_task_runner
    assert task_runner.run(**valid_run_params.merge(verify_result: true))

    assert_logs_match_all([
      "Phase 1: Initializing deploy",
      "Rendering template for task runner pod",
      "Changed Pod RestartPolicy from 'OnFailure' to 'Never'. Use'--skip-wait=true' to use 'OnFailure'.",
      "Result: SUCCESS"
    ])
  end

  def test_run_bang_works
    deploy_fixtures("hello-cloud", subset: ["template-runner.yml"])

    task_runner = build_task_runner
    assert_raises(KubernetesDeploy::FatalDeploymentError) do
      task_runner.run!(**valid_run_params)
    end

    assert_logs_match(/Starting task runner/)
    pods = kubeclient.get_pods(namespace: @namespace)
    assert_equal 1, pods.length, "Expected 1 pod to exist, found #{pods.length}"
  end

  def test_run_substitutes_arguments
    deploy_fixtures("hello-cloud", subset: ["template-runner.yml", "configmap-data.yml"])

    task_runner = build_task_runner
    refute task_runner.run(
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
    assert_logs_match("Configuration invalid: namespace was not found")
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

  def test_run_with_env_vars
    deploy_fixtures("hello-cloud", subset: ["template-runner.yml", "configmap-data.yml"])

    task_runner = build_task_runner
    refute task_runner.run(
      task_template: 'hello-cloud-template-runner',
      entrypoint: nil,
      args: %w(rake some_task),
      env_vars: ['ENV=VAR1']
    )

    pods = kubeclient.get_pods(namespace: @namespace)
    assert_equal 1, pods.length, "Expected 1 pod to exist, found #{pods.length}"
    assert_equal %w(rake some_task), pods.first.spec.containers.first.args
    assert_equal 'ENV', pods.first.spec.containers.first.env.last.name
    assert_equal 'VAR1', pods.first.spec.containers.first.env.last.value
  end

  private

  def valid_run_params
    { task_template: 'hello-cloud-template-runner', entrypoint: ['/bin/sh', '-c'], args: ["echo 'KUBERNETES-DEPLOY'"] }
  end

  def build_task_runner(ns: @namespace, max_watch_seconds: nil)
    KubernetesDeploy::RunnerTask.new(context: KubeclientHelper::MINIKUBE_CONTEXT, namespace: ns, logger: logger,
      max_watch_seconds: max_watch_seconds)
  end
end
