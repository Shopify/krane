# frozen_string_literal: true
require 'krane/runner_task'

module TaskRunnerTestHelper
  def deploy_task_template(subset = ["template-runner.yml", "configmap-data.yml"])
    EnvTestHelper.with_env("PRINT_LOGS", "0") do
      result = deploy_fixtures("hello-cloud", subset: subset) do |fixtures|
        yield fixtures if block_given?
      end
      logging_assertion do |logs|
        assert_equal true, result, "Deploy failed when it was expected to succeed: \n#{logs}"
      end
    end
    reset_logger
  end

  def build_task_runner(context: KubeclientHelper::TEST_CONTEXT, ns: @namespace, max_watch_seconds: nil)
    Krane::RunnerTask.new(context: context, namespace: ns, logger: logger,
      max_watch_seconds: max_watch_seconds)
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
        "done",
      ],
      verify_result: verify_result,
    }
  end
end
