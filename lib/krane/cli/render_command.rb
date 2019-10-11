# frozen_string_literal: true

module Krane
  module CLI
    class RenderCommand
      OPTIONS = {
        bindings: { type: :array, desc: 'Bindings for erb' },
        filenames: { type: :array, required: true, aliases: 'f', desc: 'Directories and files to render' },
      }

      def self.from_options(options)
        require 'krane/render_task'
        require 'krane/bindings_parser'
        require 'krane/options_helper'

        bindings_parser = KubernetesDeploy::BindingsParser.new
        options[:bindings]&.each { |b| bindings_parser.add(b) }

        KubernetesDeploy::OptionsHelper.with_processed_template_paths(options[:filenames]) do |paths|
          runner = KubernetesDeploy::RenderTask.new(
            current_sha: ENV["REVISION"],
            template_paths: paths,
            bindings: bindings_parser.parse,
          )
          runner.run!(STDOUT)
        end
      end
    end
  end
end
