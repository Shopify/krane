# frozen_string_literal: true

module Krane
  module CLI
    class RestartCommand
      DEFAULT_RESTART_TIMEOUT = '300s'
      OPTIONS = {
        "deployments" => { type: :array, banner: "list of deployments",
                           desc: "List of workload names to restart" },
        "global-timeout" => { type: :string, banner: "duration", default: DEFAULT_RESTART_TIMEOUT,
                              desc: "Max duration to monitor workloads correctly restarted" },
        "selector" => { type: :string, banner: "'label=value'",
                        desc: "Select workloads by selector(s)" },
        "verify-result" => { type: :boolean, default: true,
                             desc: "Verify workloads correctly restarted" },
      }

      def self.from_options(namespace, context, options)
        require 'kubernetes-deploy/restart_task'
        selector = KubernetesDeploy::LabelSelector.parse(options[:selector]) if options[:selector]
        restart = KubernetesDeploy::RestartTask.new(
          namespace: namespace,
          context: context,
          max_watch_seconds: KubernetesDeploy::DurationParser.new(options["global-timeout"]).parse!.to_i,
        )
        restart.run!(
          options[:deployments],
          selector: selector,
          verify_result: options["verify-result"]
        )
      end
    end
  end
end
