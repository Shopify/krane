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
          required: true,
        },
        "env-vars" => {
          type: :string,
          banner: "VAR=val,FOO=bar",
          desc: "A Comma-separated list of env vars",
          default: '',
        },
      }

      def self.from_options(namespace, context, options)
        require "krane/runner_task"
        runner = ::Krane::RunnerTask.new(
          namespace: namespace,
          context: context,
          global_timeout: ::Krane::DurationParser.new(options["global-timeout"]).parse!.to_i,
        )

        runner.run!(
          verify_result: options['verify-result'],
          template: options['template'],
          command: options['command'],
          arguments: options['arguments']&.split(" "),
          env_vars: options['env-vars'].split(','),
        )
      end
    end
  end
end
