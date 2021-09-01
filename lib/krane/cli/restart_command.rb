# frozen_string_literal: true

module Krane
  module CLI
    class RestartCommand
      DEFAULT_RESTART_TIMEOUT = '300s'
      OPTIONS = {
        "deployments" => { type: :array, banner: "list of deployments",
                           desc: "List of workload names to restart", default: [] },
        "stateful-sets" => { type: :array, banner: "list of deployments",
                             desc: "List of workload names to restart", default: [] },
        "daemonsets" => { type: :array, banner: "list of deployments",
                          desc: "List of workload names to restart", default: [] },
        "global-timeout" => { type: :string, banner: "duration", default: DEFAULT_RESTART_TIMEOUT,
                              desc: "Max duration to monitor workloads correctly restarted" },
        "selector" => { type: :string, banner: "'label=value'",
                        desc: "Select workloads by selector(s)" },
        "verify-result" => { type: :boolean, default: true,
                             desc: "Verify workloads correctly restarted" },
      }

      def self.from_options(namespace, context, options)
        require 'krane/restart_task'
        selector = ::Krane::LabelSelector.parse(options[:selector]) if options[:selector]
        restart = ::Krane::RestartTask.new(
          namespace: namespace,
          context: context,
          global_timeout: ::Krane::DurationParser.new(options["global-timeout"]).parse!.to_i,
        )
        restart.run!(
          deployments: options[:deployments],
          stateful_sets: options[:stateful_sets],
          daemonsets: options[:daemonsets],
          selector: selector,
          verify_result: options["verify-result"]
        )
      end
    end
  end
end
