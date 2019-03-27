# frozen_string_literal: true

module KubernetesDeploy
  module OptionsHelper
    class OptionsError < StandardError; end

    STDIN_TEMP_FILE = "from_stdin.yml.erb"
    class << self
      def with_validated_template_dir(template_dir)
        if template_dir == '-'
          Dir.mktmpdir("kubernetes-deploy") do |dir|
            template_dir_from_stdin(temp_dir: dir)
            yield dir
          end
        elsif template_dir
          yield template_dir
        else
          yield default_template_dir(template_dir)
        end
      end

      private

      def default_template_dir(template_dir)
        if ENV.key?("ENVIRONMENT")
          template_dir = File.join("config", "deploy", ENV['ENVIRONMENT'])
        end

        if !template_dir || template_dir.empty?
          raise OptionsError, "Template directory is unknown. " \
            "Either specify --template-dir argument or set $ENVIRONMENT to use config/deploy/$ENVIRONMENT " \
            "as a default path."
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
