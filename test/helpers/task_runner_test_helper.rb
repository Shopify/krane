# frozen_string_literal: true
require 'krane/runner_task'

module TaskRunnerTestHelper
  def deploy_task_template(subset = ["template-runner.yml", "configmap-data.yml"])
    EnvTestHelper.with_env("PRINT_LOGS", "0") do
      result = deploy_fixtures("hello-cloud", subset: subset) do |fixtures|
        yield fixtures if block_given?
      end
      logging_assertion do |logs|
        assert_equal(true, result, "Deploy failed when it was expected to succeed: \n#{logs}")
      end
    end
    reset_logger
  end

  def build_task_runner(context: KubeclientHelper::TEST_CONTEXT, ns: @namespace, global_timeout: nil)
    Krane::RunnerTask.new(context: context, namespace: ns, logger: logger,
      global_timeout: global_timeout)
  end

  def run_params(log_lines: 5, log_interval: 0.1, verify_result: true)
    {
      template: 'hello-cloud-template-runner',
      command: ['/bin/sh', '-c'],
      arguments: [
        "i=1; " \
        "while [ $i -le #{log_lines} ]; do " \
          "echo \"Line $i\"; " \
          "sleep #{log_interval};" \
          "i=$((i+1)); " \
        "done",
      ],
      verify_result: verify_result,
    }
  end
end
