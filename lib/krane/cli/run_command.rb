# frozen_string_literal: true

module Krane
  module CLI
    class RunCommand
      DEFAULT_RUN_TIMEOUT = '300s'

      OPTIONS = {
        "global-timeout" => {
          type: :string,
          banner: "duration",
          desc: "Timeout error is raised if the pod runs for longer than the specified number of seconds",
          default: DEFAULT_RUN_TIMEOUT,
        },
        "arguments" => {
          type: :string,
          banner: '"ARG1 ARG2 ARG3"',
          desc: "Override the default arguments for the command with a space-separated list of arguments",
        },
        "verify-result" => { type: :boolean, desc: "Wait for completion and verify pod success", default: true },
        "command" => { type: :array, desc: "Override the default command in the container image" },
        "template" => {
          type: :string,
          desc: "The template file you'll be rendering",
          default: 'task-runner-template',
        },
        "env-vars" => {
          type: :hash,
          banner: "VAR:val FOO:bar",
          desc: "A space-separated list of environment variables written as e.g. PORT:8000",
          default: {},
        },
      }

      def self.from_options(namespace, context, options)
        require "kubernetes-deploy/runner_task"
        runner = KubernetesDeploy::RunnerTask.new(
          namespace: namespace,
          context: context,
          max_watch_seconds: KubernetesDeploy::DurationParser.new(options["global-timeout"]).parse!.to_i,
        )

        runner.run!(
          verify_result: options['verify-result'],
          task_template: options['template'],
          entrypoint: options['command'],
          args: options['arguments']&.split(" "),
          env_vars: options['env-vars'],
        )
      end
    end
  end
end
