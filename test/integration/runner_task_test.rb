# frozen_string_literal: true
require 'integration_test_helper'

class RunnerTaskTest < KubernetesDeploy::IntegrationTest
  include TaskRunnerTestHelper

  def test_run_without_verify_result_succeeds_as_soon_as_pod_is_successfully_created
    deploy_unschedulable_task_template

    task_runner = build_task_runner
    assert_nil(task_runner.pod_name)
    result = task_runner.run(run_params(verify_result: false))
    assert_task_run_success(result)

    assert_logs_match_all([
      /Creating pod 'task-runner-\w+'/,
      "Pod creation succeeded",
      "Result: SUCCESS",
      "Result verification is disabled for this task",
      "The following status was observed immediately after pod creation:",
      %r{Pod/task-runner-\w+\s+(Pending|Running)},
    ], in_order: true)

    pods = kubeclient.get_pods(namespace: @namespace)
    assert_equal(1, pods.length, "Expected 1 pod to exist, found #{pods.length}")
    assert_equal(task_runner.pod_name, pods.first.metadata.name, "Pod name should be available after run")
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
      /Final status\: (Pending|Running)/,
    ], in_order: true)
  end

  def test_run_with_verify_result_failure
    deploy_task_template

    task_runner = build_task_runner
    result = task_runner.run(run_params.merge(args: ["/not/a/command"]))
    assert_task_run_failure(result)

    assert_logs_match_all([
      "Streaming logs",
      "/bin/sh: /not/a/command: not found",
      %r{Pod/task-runner-\w+ failed to run after \d+.\ds},
      "Result: FAILURE",
      "Pod status: Failed",
    ], in_order: true)
    refute_logs_match("Logs: None found")

    pods = kubeclient.get_pods(namespace: @namespace)
    assert_equal(1, pods.length, "Expected 1 pod to exist, found #{pods.length}")
    assert_equal(task_runner.pod_name, pods.first.metadata.name, "Pod name should be available after run")
  end

  def test_run_with_verify_result_success
    deploy_task_template

    task_runner = build_task_runner
    assert_nil(task_runner.pod_name)
    result = task_runner.run(run_params(log_lines: 8, log_interval: 0.25))
    assert_task_run_success(result)

    assert_logs_match_all([
      "Initializing task",
      /Using namespace 'k8sdeploy-test-run-with-verify-result-success-\w+' in context '[\w-]+'/,
      "Using template 'hello-cloud-template-runner'",
      "Running pod",
      /Creating pod 'task-runner-\w+'/,
      "Pod creation succeeded",
      "Streaming logs",
      "Line 1",
      "Line 8",
      "Result: SUCCESS",
      %r{Pod/task-runner-\w+\s+Succeeded},
    ])
    pods = kubeclient.get_pods(namespace: @namespace)
    assert_equal(1, pods.length, "Expected 1 pod to exist, found #{pods.length}")
    assert_equal(task_runner.pod_name, pods.first.metadata.name, "Pod name should be available after run")
  end

  def test_run_with_verify_result_fails_quickly_if_the_pod_is_deleted_out_of_band
    deploy_task_template

    task_runner = build_task_runner
    deleter_thread = Thread.new do
      loop do
        if task_runner.pod_name.present?
          begin
            kubeclient.delete_pod(task_runner.pod_name, @namespace)
            break
          rescue Kubeclient::ResourceNotFoundError
            sleep(0.1)
            retry
          end
        end
        sleep 0.1
      end
    end
    deleter_thread.abort_on_exception = true

    result = task_runner.run(run_params(log_lines: 20, log_interval: 1))
    assert_task_run_failure(result)

    assert_logs_match_all([
      "Pod creation succeeded",
      "Result: FAILURE",
      /Pod status\: (Terminating|Disappeared)/,
    ])
  ensure
    deleter_thread&.kill
  end

  def test_run_with_verify_result_neither_misses_nor_duplicates_logs_across_pollings
    deploy_task_template
    task_runner = build_task_runner
    result = task_runner.run(run_params(log_lines: 5_000, log_interval: 0.0005))
    assert_task_run_success(result)

    logging_assertion do |all_logs|
      nums_printed = all_logs.scan(/Line (\d+)$/).flatten

      first_num_printed = nums_printed[0].to_i
      # The first time we fetch logs, we grab at most 250 lines, so we likely won't print the first few hundred
      assert first_num_printed < 1500, "Unexpected number of initial logs skipped (started with #{first_num_printed})"

      expected_nums = (first_num_printed..5_000).map(&:to_s)
      missing_nums = expected_nums - nums_printed.uniq
      assert missing_nums.empty?, "Some lines were not streamed: #{missing_nums}"

      num_lines_duplicated = nums_printed.length - nums_printed.uniq.length
      assert num_lines_duplicated.zero?, "#{num_lines_duplicated} lines were duplicated"
    end
  end

  def test_run_with_bad_restart_policy
    deploy_task_template do |fixtures|
      fixtures["template-runner.yml"]["PodTemplate"].first["template"]["spec"]["restartPolicy"] = "OnFailure"
    end

    task_runner = build_task_runner
    assert_task_run_success(task_runner.run(run_params))

    assert_logs_match_all([
      "Phase 1: Initializing task",
      "Using template 'hello-cloud-template-runner'",
      "Changed Pod RestartPolicy from 'OnFailure' to 'Never'. Disable result verification to use 'OnFailure'.",
      "Phase 2: Running pod",
    ])
  end

  def test_run_bang_raises_exceptions_as_well_as_printing_failure
    deploy_task_template

    task_runner = build_task_runner
    assert_raises(KubernetesDeploy::FatalDeploymentError) do
      task_runner.run!(run_params.merge(args: ["/not/a/command"]))
    end

    assert_logs_match_all([
      "Streaming logs",
      "/bin/sh: /not/a/command: not found",
      %r{Pod/task-runner-\w+ failed to run after \d+.\ds},
      "Result: FAILURE",
      "Pod status: Failed",
    ], in_order: true)

    pods = kubeclient.get_pods(namespace: @namespace)
    assert_equal(1, pods.length, "Expected 1 pod to exist, found #{pods.length}")
  end

  def test_run_fails_if_context_is_invalid
    task_runner = build_task_runner(context: "unknown")
    assert_task_run_failure(task_runner.run(run_params))

    assert_logs_match_all([
      "Initializing task",
      "Validating configuration",
      "Result: FAILURE",
      "Configuration invalid",
      "Context unknown missing from your kubeconfig file(s)",
    ], in_order: true)
  end

  def test_run_fails_if_namespace_is_missing
    task_runner = build_task_runner(ns: "missing")
    assert_task_run_failure(task_runner.run(run_params))

    assert_logs_match_all([
      "Initializing task",
      "Validating configuration",
      "Result: FAILURE",
      "Configuration invalid",
      "Could not find Namespace:",
    ], in_order: true)
  end

  def test_run_fails_if_args_are_missing
    task_runner = build_task_runner
    result = task_runner.run(task_template: 'hello-cloud-template-runner',
      entrypoint: ['/bin/sh', '-c'],
      args: nil,
      env_vars: ["MY_CUSTOM_VARIABLE=MITTENS"])
    assert_task_run_failure(result)

    assert_logs_match_all([
      "Initializing task",
      "Validating configuration",
      "Result: FAILURE",
      "Configuration invalid",
      "Args can't be nil",
    ], in_order: true)
  end

  def test_run_fails_if_task_template_is_blank
    task_runner = build_task_runner
    result = task_runner.run(task_template: '',
      entrypoint: ['/bin/sh', '-c'],
      args: nil,
      env_vars: ["MY_CUSTOM_VARIABLE=MITTENS"])
    assert_task_run_failure(result)

    assert_logs_match_all([
      "Initializing task",
      "Validating configuration",
      "Result: FAILURE",
      "Configuration invalid",
      "Task template name can't be nil",
    ], in_order: true)
  end

  def test_run_bang_fails_if_task_template_or_args_are_invalid
    task_runner = build_task_runner
    assert_raises(KubernetesDeploy::TaskConfigurationError) do
      task_runner.run!(task_template: '',
        entrypoint: ['/bin/sh', '-c'],
        args: nil,
        env_vars: ["MY_CUSTOM_VARIABLE=MITTENS"])
    end
  end

  def test_run_with_template_missing
    task_runner = build_task_runner
    assert_task_run_failure(task_runner.run(run_params))
    message = "Pod template `hello-cloud-template-runner` not found in namespace `#{@namespace}`, " \
      "context `#{KubeclientHelper::TEST_CONTEXT}`"
    assert_logs_match_all([
      "Result: FAILURE",
      message,
    ], in_order: true)

    assert_raises_message(KubernetesDeploy::RunnerTask::TaskTemplateMissingError, message) do
      task_runner.run!(run_params)
    end
  end

  def test_run_with_pod_spec_template_missing
    deploy_task_template do |fixtures|
      template = fixtures["template-runner.yml"]["PodTemplate"].first["template"]
      template["spec"]["containers"].first["name"] = "bad-name"
    end

    task_runner = build_task_runner
    assert_task_run_failure(task_runner.run(run_params))
    message = "Pod spec does not contain a template container called 'task-runner'"

    assert_raises_message(KubernetesDeploy::TaskConfigurationError, message) do
      task_runner.run!(run_params)
    end

    assert_logs_match_all([
      "Result: FAILURE",
      message,
    ], in_order: true)
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
      "The value is: MITTENS",
    ], in_order: true)
  end

  private

  def deploy_unschedulable_task_template
    deploy_task_template do |fixtures|
      way_too_fat = {
        "requests" => {
          "cpu" => 1000,
          "memory" => "100Gi",
        },
      }
      template = fixtures["template-runner.yml"]["PodTemplate"].first["template"]
      template["spec"]["containers"].first["resources"] = way_too_fat
    end
  end
end
