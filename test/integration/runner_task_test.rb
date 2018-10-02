# frozen_string_literal: true
require 'test_helper'

require 'kubernetes-deploy/runner_task'
class RunnerTaskTest < KubernetesDeploy::IntegrationTest
  include EnvTestHelper

  def test_run_without_verify_result_succeeds_as_soon_as_pod_is_successfully_created
    deploy_task_template

    task_runner = build_task_runner
    result = task_runner.run(run_params(verify_result: false))
    assert_task_run_success(result)

    assert_logs_match_all([
      /Pod 'task-runner-\w+' created/,
      "Result: SUCCESS",
      "Pod created",
      "Result verification is disabled for this task"
    ], in_order: true)
    pods = kubeclient.get_pods(namespace: @namespace)
    assert_equal 1, pods.length, "Expected 1 pod to exist, found #{pods.length}"
  end

  def test_run_without_verify_result_fails_if_pod_was_not_created
    deploy_task_template
    task_runner = build_task_runner

    # Sketchy, but stubbing the kubeclient doesn't work (and wouldn't be concurrency-friendly)
    # Finding a way to reliably trigger a create failure would be much better, if possible
    mock = mock()
    mock.expects(:get_namespace)
    template = kubeclient.get_pod_template('hello-cloud-template-runner', @namespace)
    mock.expects(:get_pod_template).returns(template)
    mock.expects(:create_pod).raises(Kubeclient::HttpError.new("409", "Pod with same name exists", {}))
    task_runner.instance_variable_set(:@kubeclient, mock)

    result = task_runner.run(run_params(verify_result: false))
    assert_task_run_failure(result)

    assert_logs_match_all([
      "Running pod",
      "Result: FAILURE",
      "Failed to create pod",
      "Kubeclient::HttpError: Pod with same name exists"
    ], in_order: true)
  end

  def test_run_global_timeout_with_max_watch_seconds
    deploy_task_template

    task_runner = build_task_runner(max_watch_seconds: 5)
    result = task_runner.run(run_params(log_lines: 8, log_interval: 1))
    assert_task_run_failure(result, :timed_out)

    assert_logs_match_all([
      "Result: TIMED OUT",
      "Timed out waiting for 1 resource to run",
      %r{Pod/task-runner-\w+: GLOBAL WATCH TIMEOUT \(5 seconds\)},
      "Final status: Running"
    ], in_order: true)
  end

  def test_run_with_verify_result_failure
    deploy_task_template

    task_runner = build_task_runner
    result = task_runner.run(run_params.merge(args: ["echo 'emit a log'; FAKE"]))
    assert_task_run_failure(result)

    assert_logs_match_all([
      "Streaming logs",
      "emit a log",
      "/bin/sh: FAKE: not found",
      %r{Pod/task-runner-\w+ failed to run after \d+.\ds},
      "Result: FAILURE",
      "Pod status: Failed"
    ], in_order: true)
  end

  def test_run_with_verify_result_success
    deploy_task_template

    task_runner = build_task_runner
    result = task_runner.run(run_params(log_lines: 8, log_interval: 0.25))
    assert_task_run_success(result)

    assert_logs_match_all([
      "Running pod",
      /Pod 'task-runner-\w+' created/,
      "Streaming logs",
      "Line 1",
      "Line 8",
      "Result: SUCCESS",
      "Successfully ran 1 resource",
    ])
    pods = kubeclient.get_pods(namespace: @namespace)
    assert_equal 1, pods.length, "Expected 1 pod to exist, found #{pods.length}"
  end

  def test_run_with_verify_result_neither_misses_nor_duplicates_logs_across_pollings
    deploy_task_template
    task_runner = build_task_runner
    result = task_runner.run(run_params(log_lines: 5_000, log_interval: 0.0001))
    assert_task_run_success(result)

    logging_assertion do |all_logs|
      nums_printed = all_logs.scan(/Line (\d+)$/).flatten

      missing_nums = nums_printed - (1..5_000).map(&:to_s)
      refute missing_nums.present?, "Some lines were not streamed: #{missing_nums}"

      num_lines_duplicated = nums_printed.length - nums_printed.uniq.length
      assert num_lines_duplicated.zero?, "#{num_lines_duplicated} lines were duplicated"
    end
  end

  def test_run_with_bad_restart_policy
    deploy_task_template do |f|
      f["template-runner.yml"]["PodTemplate"].first["template"]["spec"]["restartPolicy"] = "OnFailure"
    end

    task_runner = build_task_runner
    assert_task_run_success(task_runner.run(run_params))

    assert_logs_match_all([
      "Phase 1: Initializing task",
      "Using template 'hello-cloud-template-runner' from namespace '#{@namespace}'",
      "Changed Pod RestartPolicy from 'OnFailure' to 'Never'. Disable result verification to use 'OnFailure'.",
      "Phase 2: Running pod"
    ])
  end

  def test_run_bang_raises_exceptions_as_well_as_printing_failure
    deploy_task_template

    task_runner = build_task_runner
    assert_raises(KubernetesDeploy::FatalDeploymentError) do
      task_runner.run!(run_params.merge(args: ["echo 'emit a log'; FAKE"]))
    end

    assert_logs_match_all([
      "Streaming logs",
      "emit a log",
      "/bin/sh: FAKE: not found",
      %r{Pod/task-runner-\w+ failed to run after \d+.\ds},
      "Result: FAILURE",
      "Pod status: Failed"
    ], in_order: true)

    pods = kubeclient.get_pods(namespace: @namespace)
    assert_equal 1, pods.length, "Expected 1 pod to exist, found #{pods.length}"
  end

  def test_run_with_missing_namespace
    task_runner = build_task_runner(ns: "missing")
    assert_task_run_failure(task_runner.run(run_params))

    assert_logs_match_all([
      "Initializing task",
      "Validating configuration",
      "Result: FAILURE",
      "Configuration invalid",
      "- Namespace was not found"
    ], in_order: true)
  end

  def test_run_with_template_missing
    task_runner = build_task_runner
    assert_task_run_failure(task_runner.run(run_params))
    message = "Pod template `hello-cloud-template-runner` not found in namespace `#{@namespace}`, " \
      "context `#{KubeclientHelper::MINIKUBE_CONTEXT}`"
    assert_logs_match_all([
      "Result: FAILURE",
      message
    ], in_order: true)

    assert_raises_message(KubernetesDeploy::RunnerTask::TaskTemplateMissingError, message) do
      task_runner.run!(run_params)
    end
  end

  def test_run_adds_env_vars_provided_to_the_task_container
    deploy_task_template

    task_runner = build_task_runner
    result = task_runner.run(
      task_template: 'hello-cloud-template-runner',
      entrypoint: ['/bin/sh', '-c'],
      args: ['echo "The value is: $MY_CUSTOM_VARIABLE"'],
      env_vars: ["MY_CUSTOM_VARIABLE=MITTENS"]
    )
    assert_task_run_success(result)

    assert_logs_match_all([
      "Streaming logs",
      "The value is: MITTENS"
    ], in_order: true)
  end

  private

  def deploy_task_template(subset = ["template-runner.yml", "configmap-data.yml"])
    with_env("PRINT_LOGS", "0") do
      result = deploy_fixtures("hello-cloud", subset: subset) do |fixtures|
        yield fixtures if block_given?
      end
      assert_deploy_success(result)
    end
    reset_logger
  end

  def run_params(log_lines: 5, log_interval: 0.1, verify_result: true)
    {
      task_template: 'hello-cloud-template-runner',
      entrypoint: ['/bin/sh', '-c'],
      args: [
        "i=1; " \
        "while [ $i -le #{log_lines} ]; do " \
          "echo \"Line $i\"; " \
          "sleep #{log_interval};" \
          "i=$((i+1)); " \
        "done"
      ],
      verify_result: verify_result
    }
  end

  def build_task_runner(ns: @namespace, max_watch_seconds: nil)
    KubernetesDeploy::RunnerTask.new(context: KubeclientHelper::MINIKUBE_CONTEXT, namespace: ns, logger: logger,
      max_watch_seconds: max_watch_seconds)
  end
end
