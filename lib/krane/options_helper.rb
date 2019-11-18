# frozen_string_literal: true

module Krane
  module OptionsHelper
    class OptionsError < StandardError; end

    STDIN_TEMP_FILE = "from_stdin.yml"
    class << self
      def with_processed_template_paths(template_paths, render_erb: false)
        validated_paths = []
        template_paths.uniq!
        template_paths.each do |template_path|
          next if template_path == '-'
          validated_paths << template_path
        end

        if template_paths.include?("-")
          Dir.mktmpdir("krane") do |dir|
            template_dir_from_stdin(temp_dir: dir, render_erb: render_erb)
            validated_paths << dir
            yield validated_paths
          end
        else
          yield validated_paths
        end
      end

      private

      def template_dir_from_stdin(temp_dir:, render_erb:)
        tempfile = STDIN_TEMP_FILE
        tempfile += ".erb" if render_erb
        File.open(File.join(temp_dir, tempfile), 'w+') { |f| f.print($stdin.read) }
      rescue IOError, Errno::ENOENT => e
        raise OptionsError, e.message
      end
    end
  end
end
