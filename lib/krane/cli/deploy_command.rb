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
                         aliases: :f, required: false, default: [],
                         desc: "Directories and files that contains the configuration to apply" },
        "stdin" => { type: :boolean, default: false,
                     desc: "[DEPRECATED] Read resources from stdin" },
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
        "selector-as-filter" => { type: :boolean,
                                  desc: "Use --selector as a label filter to deploy only a subset "\
                                    "of the provided resources",
                                  default: false },
        "verbose-log-prefix" => { type: :boolean, desc: "Add [context][namespace] to the log prefix",
                                  default: false },
        "verify-result" => { type: :boolean, default: true,
                             desc: "Verify workloads correctly deployed" },
      }

      def self.from_options(namespace, context, options)
        require 'krane/deploy_task'
        require 'krane/options_helper'
        require 'krane/label_selector'

        selector = ::Krane::LabelSelector.parse(options[:selector]) if options[:selector]
        selector_as_filter = options['selector-as-filter']

        if selector_as_filter && !selector
          raise(Thor::RequiredArgumentMissingError, '--selector must be set when --selector-as-filter is set')
        end

        logger = ::Krane::FormattedLogger.build(namespace, context,
          verbose_prefix: options['verbose-log-prefix'])

        protected_namespaces = options['protected-namespaces']
        if options['protected-namespaces'].size == 1 && %w('' "").include?(options['protected-namespaces'][0])
          protected_namespaces = []
        end

        filenames = options[:filenames].dup
        filenames << "-" if options[:stdin]
        if filenames.empty?
          raise(Thor::RequiredArgumentMissingError, '--filenames must be set and not empty')
        end

        ::Krane::OptionsHelper.with_processed_template_paths(filenames) do |paths|
          deploy = ::Krane::DeployTask.new(
            namespace: namespace,
            context: context,
            filenames: paths,
            logger: logger,
            global_timeout: ::Krane::DurationParser.new(options["global-timeout"]).parse!.to_i,
            selector: selector,
            selector_as_filter: selector_as_filter,
            protected_namespaces: protected_namespaces,
          )

          deploy.run!(
            verify_result: options["verify-result"],
            prune: options[:prune]
          )
        end
      end
    end
  end
end
