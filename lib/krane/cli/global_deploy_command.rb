# frozen_string_literal: true

module Krane
  module CLI
    class GlobalDeployCommand
      DEFAULT_DEPLOY_TIMEOUT = '300s'
      OPTIONS = {
        "filenames" => { type: :string, banner: '/tmp/my-resource.yml', aliases: :f, required: true,
                         desc: "Path to file or directory that contains the configuration to apply" },
        "global-timeout" => { type: :string, banner: "duration", default: DEFAULT_DEPLOY_TIMEOUT,
                              desc: "Max duration to monitor workloads correctly deployed" },
        "verify-result" => { type: :boolean, default: true,
                             desc: "Verify workloads correctly deployed" },
        "selector" => { type: :string, banner: "'label=value'", required: true,
                        desc: "Select workloads by selector(s)" },
      }

      def self.from_options(context, options)
        require 'krane/global_deploy_task'
        require 'kubernetes-deploy/options_helper'
        require 'kubernetes-deploy/label_selector'

        selector = KubernetesDeploy::LabelSelector.parse(options[:selector])

        KubernetesDeploy::OptionsHelper.with_processed_template_paths([options[:filenames]],
          require_explicit_path: true) do |paths|
          deploy = ::Krane::GlobalDeployTask.new(
            context: context,
            current_sha: ENV["REVISION"],
            template_paths: paths,
            max_watch_seconds: KubernetesDeploy::DurationParser.new(options["global-timeout"]).parse!.to_i,
            selector: selector,
          )

          deploy.run!(
            verify_result: options["verify-result"],
            prune: false,
          )
        end
      end
    end
  end
end
