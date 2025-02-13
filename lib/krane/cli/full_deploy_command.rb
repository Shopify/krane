# frozen_string_literal: true

require 'krane/cli/deploy_command'
require 'krane/cli/global_deploy_command'

module Krane
  module CLI
    class FullDeployCommand
      DEFAULT_DEPLOY_TIMEOUT = "300s"
      OPTIONS = {
        # Command args
        "filenames" => {
          type: :array,
          banner: "config/deploy/production config/deploy/my-extra-resource.yml",
          aliases: :f,
          required: false,
          default: [],
          desc: "Directories and files that contains the configuration to apply",
        },
        "stdin" => {
          type: :boolean,
          default: false,
          desc: "[DEPRECATED] Read resources from stdin",
        },
        "verbose-log-prefix" => {
          type: :boolean,
          desc: "Add [context][namespace] to the log prefix",
          default: false,
        },

        # Global deploy args
        "global-selector" => {
          type: :string,
          banner: "'label=value'",
          required: true,
          desc: "Select workloads owned by selector(s)",
        },
        "global-selector-as-filter" => {
          type: :boolean,
          desc: "Use --selector as a label filter to deploy only a subset " \
            "of the provided resources",
          default: false,
        },
        "global-prune" => {
          type: :boolean,
          desc: "Enable deletion of resources that match " \
            "the provided selector and do not appear in the provided templates",
          default: true,
        },
        "global-verify-result" => {
          type: :boolean,
          default: true,
          desc: "Verify workloads correctly deployed",
        },

        # Namespaced deploy args
        "protected-namespaces" => {
          type: :array,
          banner: "namespace1 namespace2 namespaceN",
          desc: "Enable deploys to a list of selected namespaces; set to an empty string " \
            "to disable",
          default: DeployCommand::PROTECTED_NAMESPACES,
        },
        "prune" => {
          type: :boolean,
          desc: "Enable deletion of resources that do not appear in the template dir",
          default: true,
        },
        "selector-as-filter" => {
          type: :boolean,
          desc: "Use --selector as a label filter to deploy only a subset " \
            "of the provided resources",
          default: false,
        },
        "selector" => {
          type: :string,
          banner: "'label=value'",
          desc: "Select workloads by selector(s)",
        },
        "verify-result" => {
          type: :boolean,
          default: true,
          desc: "Verify workloads correctly deployed",
        },
      }

      def self.from_options(namespace, context, options)
        require 'krane/global_deploy_task'
        require 'krane/options_helper'
        require 'krane/label_selector'
        require 'krane/duration_parser'

        logger = ::Krane::FormattedLogger.build(namespace, context, verbose_prefix: options['verbose-log-prefix'])

        protected_namespaces = options['protected-namespaces']
        if options['protected-namespaces'].size == 1 && %w('' "").include?(options['protected-namespaces'][0])
          protected_namespaces = []
        end

        global_selector = ::Krane::LabelSelector.parse(options["global-selector"])
        global_selector_as_filter = options['selector-as-filter']
        if global_selector_as_filter && !global_selector
          raise(Thor::RequiredArgumentMissingError, '--selector must be set when --selector-as-filter is set')
        end

        selector = ::Krane::LabelSelector.parse(options[:selector]) if options[:selector]
        selector_as_filter = options['selector-as-filter']
        if selector_as_filter && !selector
          raise(Thor::RequiredArgumentMissingError, '--selector must be set when --selector-as-filter is set')
        end

        filenames = options[:filenames].dup
        filenames << "-" if options[:stdin]
        if filenames.empty?
          raise(Thor::RequiredArgumentMissingError, '--filenames must be set and not empty')
        end

        ::Krane::OptionsHelper.with_processed_template_paths(filenames) do |paths|
          full_deploy = ::Krane::FullDeployTask.new(
            namespace: namespace,
            context: context,
            filenames: paths,
            logger: logger,
            selector: selector,
            selector_as_filter: selector_as_filter,
            protected_namespaces: protected_namespaces,
            global_timeout: ::Krane::DurationParser.new(options["global-timeout"]).parse!.to_i,
            global_selector: global_selector,
            global_selector_as_filter: global_selector_as_filter,
          )

          full_deploy.run!(
            global_prune: options['global-prune'],
            global_verify_result: options['global-verify-result'],
            verify_result: options['verify-result'],
            prune: options('prune'),
          )
        end
      end
    end
  end
end