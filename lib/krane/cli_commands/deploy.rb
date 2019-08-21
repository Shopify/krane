# frozen_string_literal: true

module Krane
  module CLICommands
    class Deploy
      OPTIONS = {
        "verify-result" => { type: :boolean, default: true },
        "protected-namespaces" => {
          type: :string,
          default: "default,kube-system,kube-public",
          banner: "LIST,OF,NAMESPACES",
        },
        "prune" => { type: :boolean, default: true },
        "filename" => { aliases: "-f", type: :string },
        "verbose-log-prefix" => { default: false, type: :boolean },
        "verification-timeout-sec" => { default: 300, type: :numeric },
        "revision" => { type: :string },
        "selector" => { type: :string },
      }

      def self.from_options(namespace, context, options)
        require 'krane'
        selector = KubernetesDeploy::LabelSelector.parse(options["selector"]) if options["selector"]
        logger = KubernetesDeploy::FormattedLogger.build(namespace, context,
          verbose_prefix: options["verbose-log-prefix"])
        KubernetesDeploy::OptionsHelper.with_validated_template_dir(options["filename"]) do |dir|
          $stderr.puts "KubernetesDeploy::DeployTask.new(
            namespace: #{namespace},
            context: #{context},
            current_sha: #{options['revision']},
            template_dir: #{dir},
            logger: #{logger},
            max_watch_seconds: #{options['verification-timeout-sec']},
            selector: #{selector},
          )"

          $stderr.puts "runner.run!(
            verify_result: #{options['verify-result']},
            protected-namespaces: #{options['protected-namespaces']},
            prune: #{options['prune']}
          )"
        end
      rescue KubernetesDeploy::OptionsHelper::OptionsError => e
        logger.error(e.message)
        raise KubernetesDeploy::FatalDeploymentError, e.message
      end
    end
  end
end
