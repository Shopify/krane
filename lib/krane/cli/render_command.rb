# frozen_string_literal: true

module Krane
  module CLI
    class RenderCommand
      OPTIONS = {
        bindings: { type: :array, banner: "foo=bar abc=def", desc: 'Bindings for erb' },
        filenames: { type: :array, banner: 'config/deploy/production config/deploy/my-extra-resource.yml',
                     required: false, default: [], aliases: 'f', desc: 'Directories and files to render' },
        stdin: { type: :boolean, desc: "Read resources from stdin", default: false },
        'current-sha': { type: :string, banner: "SHA", desc: "Expose SHA `current_sha` in ERB bindings" },
      }

      def self.from_options(options)
        require 'krane/render_task'
        require 'krane/bindings_parser'
        require 'krane/options_helper'

        bindings_parser = ::Krane::BindingsParser.new
        options[:bindings]&.each { |b| bindings_parser.add(b) }

        options[:filenames] << "-" if options[:stdin]
        if options[:filenames].empty?
          raise Thor::RequiredArgumentMissingError, 'Must provied a value for --filenames or --stdin'
        end

        ::Krane::OptionsHelper.with_processed_template_paths(options[:filenames]) do |paths|
          runner = ::Krane::RenderTask.new(
            current_sha: options['current-sha'],
            template_paths: paths,
            bindings: bindings_parser.parse,
          )
          runner.run!(STDOUT)
        end
      end
    end
  end
end
