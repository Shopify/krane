# frozen_string_literal: true

module Krane
  module CLI
    class RestartCommand
      DEFAULT_GLOBAL_TIMEOUT = '300s'
      OPTIONS = {
        "global-timeout" => { default: DEFAULT_GLOBAL_TIMEOUT, type: :string },
        "deployments" => { type: :string },
        "selector" => { type: :string },
        "verify-result" => { type: :boolean, default: true },
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
          options[:deployments]&.split(","),
          selector: selector,
          verify_result: options["verify-result"]
        )
      end
    end
  end
end
