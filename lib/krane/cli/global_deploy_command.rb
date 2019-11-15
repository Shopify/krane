# frozen_string_literal: true

module Krane
  module CLI
    class GlobalDeployCommand
      DEFAULT_DEPLOY_TIMEOUT = '300s'
      OPTIONS = {
        "filenames" => { type: :array, banner: 'config/deploy/production config/deploy/my-extra-resource.yml',
                         aliases: :f, required: false, default: [],
                         desc: "Directories and files that contains the configuration to apply" },
        "stdin" => { type: :boolean, default: false, desc: "Read resources from stdin" },
        "global-timeout" => { type: :string, banner: "duration", default: DEFAULT_DEPLOY_TIMEOUT,
                              desc: "Max duration to monitor workloads correctly deployed" },
        "verify-result" => { type: :boolean, default: true,
                             desc: "Verify workloads correctly deployed" },
        "selector" => { type: :string, banner: "'label=value'", required: true,
                        desc: "Select workloads owned by selector(s)" },
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

        # never mutate options directly
        filenames = options[:filenames].dup
        filenames << "-" if options[:stdin]
        if filenames.empty?
          raise Thor::RequiredArgumentMissingError, 'Must provied a value for --filenames or --stdin'
        end

        ::Krane::OptionsHelper.with_processed_template_paths(filenames,
          require_explicit_path: true) do |paths|
          deploy = ::Krane::GlobalDeployTask.new(
            context: context,
            filenames: paths,
            global_timeout: ::Krane::DurationParser.new(options["global-timeout"]).parse!.to_i,
            selector: selector,
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
