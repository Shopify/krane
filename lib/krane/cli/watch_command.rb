# frozen_string_literal: true

module Krane
  module CLI
    class WatchCommand
      DEFAULT_WATCH_TIMEOUT = '300s'

      OPTIONS = {
        "filenames" => { type: :array, banner: 'config/deploy/my_rendered_templates.yml',
                         aliases: :f, required: true,
                         desc: "The path to a set of rendered kubernetes templates" },
        "global-timeout" => {
          type: :string,
          banner: "duration",
          desc: "Timeout error is raised if the pod runs for longer than the specified number of seconds",
          default: DEFAULT_WATCH_TIMEOUT,
        },
      }

      def self.from_options(namespace, context, options)
        require 'krane/watch_task'
        require 'krane/options_helper'

        ::Krane::OptionsHelper.with_processed_template_paths(options[:filenames],
          require_explicit_path: true) do |paths|
          watcher = ::Krane::WatchTask.new(
            namespace: namespace,
            context: context,
            filenames: paths,
            max_watch_seconds: ::Krane::DurationParser.new(options["global-timeout"]).parse!.to_i,
          )

          watcher.run!
        end
      end
    end
  end
end
