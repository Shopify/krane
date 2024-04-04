# frozen_string_literal: true

module Krane
  module CLI
    class DeployCommand
      OPTIONS = DeployCommand::OPTIONS.merge(GlobalDeployCommand::OPTIONS)

      def self.from_options(context, options)
        require 'krane/deploy_task'
        require 'krane/global_deploy_task'
        require 'krane/options_helper'
        require 'krane/label_selector'
        require 'krane/duration_parser'

        selector = ::Krane::LabelSelector.parse(options[:selector])
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
          deploy = ::Krane::GlobalDeployTask.new(
            context: context,
            filenames: paths,
            global_timeout: ::Krane::DurationParser.new(options["global-timeout"]).parse!.to_i,
            selector: selector,
            selector_as_filter: selector_as_filter,
          )

          deploy.run!(
            verify_result: options["verify-result"],
            prune: options[:prune],
          )
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
