# frozen_string_literal: true

module Krane
  module CLI
    class DeployCommand
      DEFAULT_DEPLOY_TIMEOUT = '300s'
      PROTECTED_NAMESPACES = %w(
        default
        kube-system
        kube-public
      )
      OPTIONS = {
        "filenames" => { type: :array, banner: 'config/deploy/production config/deploy/my-extra-resource.yml',
                         aliases: :f, required: true,
                         desc: "Directories and files that contains the configuration to apply" },
        "global-timeout" => { type: :string, banner: "duration", default: DEFAULT_DEPLOY_TIMEOUT,
                              desc: "Max duration to monitor workloads correctly deployed" },
        "protected-namespaces" => { type: :array, banner: "namespace1 namespace2 namespaceN",
                                    desc: "Enable deploys to a list of selected namespaces; set to an empty string "\
                                      "to disable",
                                    default: PROTECTED_NAMESPACES },
        "prune" => { type: :boolean, desc: "Enable deletion of resources that do not appear in the template dir",
                     default: true },
        "selector" => { type: :string, banner: "'label=value'",
                        desc: "Select workloads by selector(s)" },
        "verbose-log-prefix" => { type: :boolean, desc: "Add [context][namespace] to the log prefix",
                                  default: true },
        "verify-result" => { type: :boolean, default: true,
                             desc: "Verify workloads correctly deployed" },
        "current-sha" => { type: :string, banner: "SHA", desc: "Expose SHA `current_sha` in ERB bindings" },

      }

      def self.from_options(namespace, context, options)
        require 'krane/deploy_task'
        require 'krane/options_helper'
        require 'krane/label_selector'

        selector = ::Krane::LabelSelector.parse(options[:selector]) if options[:selector]

        logger = ::Krane::FormattedLogger.build(namespace, context,
          verbose_prefix: options['verbose-log-prefix'])

        protected_namespaces = options['protected-namespaces']
        if options['protected-namespaces'].size == 1 && %w('' "").include?(options['protected-namespaces'][0])
          protected_namespaces = []
        end

        ::Krane::OptionsHelper.with_processed_template_paths(options[:filenames],
          require_explicit_path: true) do |paths|
          deploy = ::Krane::DeployTask.new(
            namespace: namespace,
            context: context,
            current_sha: options['current-sha'],
            template_paths: paths,
            logger: logger,
            max_watch_seconds: ::Krane::DurationParser.new(options["global-timeout"]).parse!.to_i,
            selector: selector,
            protected_namespaces: protected_namespaces,
          )

          deploy.run!(
            verify_result: options["verify-result"],
            allow_protected_ns: !protected_namespaces.empty?,
            prune: options[:prune]
          )
        end
      end
    end
  end
end
