# frozen_string_literal: true

module KubernetesDeploy
  module OptionsHelper
    class OptionsError < StandardError; end

    STDIN_TEMP_FILE = "from_stdin.yml.erb"
    class << self
      def with_processed_template_paths(template_paths)
        validated_paths = []
        if template_paths.empty?
          validated_paths << default_template_dir
        else
          template_paths.uniq!
          template_paths.each do |template_path|
            next if template_path == '-'
            validated_paths << template_path
          end
        end

        if template_paths.include?("-")
          Dir.mktmpdir("kubernetes-deploy") do |dir|
            template_dir_from_stdin(temp_dir: dir)
            validated_paths << dir
            yield validated_paths
          end
        else
          yield validated_paths
        end
      end

      private

      def default_template_dir
        template_dir = if ENV.key?("ENVIRONMENT")
          File.join("config", "deploy", ENV['ENVIRONMENT'])
        end

        unless template_dir
          raise OptionsError, "Template directory is unknown. " \
          "Either specify --template-dir argument or set $ENVIRONMENT to use config/deploy/$ENVIRONMENT " \
          "as a default path."
        end
        unless Dir.exist?(template_dir)
          raise OptionsError, "Template directory #{template_dir} does not exist."
        end

        template_dir
      end

      def template_dir_from_stdin(temp_dir:)
        File.open(File.join(temp_dir, STDIN_TEMP_FILE), 'w+') { |f| f.print($stdin.read) }
      rescue IOError, Errno::ENOENT => e
        raise OptionsError, e.message
      end
    end
  end
end
