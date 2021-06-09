# frozen_string_literal: true

module Krane
  module CLI
    class GlobalDeployCommand
      DEFAULT_DEPLOY_TIMEOUT = '300s'
      OPTIONS = {
        "filenames" => { type: :array, banner: 'config/deploy/production config/deploy/my-extra-resource.yml',
                         aliases: :f, required: false, default: [],
                         desc: "Directories and files that contains the configuration to apply" },
        "stdin" => { type: :boolean, default: false,
                     desc: "[DEPRECATED] Read resources from stdin" },
        "global-timeout" => { type: :string, banner: "duration", default: DEFAULT_DEPLOY_TIMEOUT,
                              desc: "Max duration to monitor workloads correctly deployed" },
        "verify-result" => { type: :boolean, default: true,
                             desc: "Verify workloads correctly deployed" },
        "selector" => { type: :string, banner: "'label=value'", required: true,
                        desc: "Select workloads owned by selector(s)" },
        "selector-as-filter" => { type: :boolean,
                                  desc: "Use --selector as a label filter to deploy only a subset "\
                                    "of the provided resources",
                                  default: false },
        "prune" => { type: :boolean, desc: "Enable deletion of resources that match"\
                     " the provided selector and do not appear in the provided templates",
                     default: true },
      }

      def self.from_options(context, options)
        require 'krane/global_deploy_task'
        require 'krane/options_helper'
        require 'krane/label_selector'
        require 'krane/duration_parser'

        selector = ::Krane::LabelSelector.parse(options[:selector])
        selector_as_filter = options['selector-as-filter']

        if selector_as_filter && selector.to_s.empty?
          raise(Thor::RequiredArgumentMissingError, '--selector must be set when --selector-as-filter is set')
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
      end
    end
  end
end
