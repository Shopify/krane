# frozen_string_literal: true

module KubernetesDeploy
  module OptionsHelper
    class OptionsError < StandardError; end

    STDIN_TEMP_FILE = "from_stdin.yml.erb"
    class << self
      def with_consolidated_template_dir(template_dirs)
        if template_dirs.length > 1 || template_dirs.include?('-')
          Dir.mktmpdir("kubernetes-deploy") do |dir|
            populate_temp_dir(temp_dir: dir, template_dirs: template_dirs)
            yield dir
          end
        else
          yield default_template_dir(template_dirs.first)
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

      def populate_temp_dir(temp_dir:, template_dirs:)
        template_dirs.each do |template_dir|
          if template_dir == '-'
            File.open(File.join(temp_dir, STDIN_TEMP_FILE), 'w+') { |f| f.print($stdin.read) }
          else
            template_dir = File.expand_path(template_dir)
            templates = Dir.entries(template_dir).select { |f| File.file?(File.join(template_dir, f)) }
            templates.each do |template|
              FileUtils.cp(
                File.join(template_dir, template),
                File.join(temp_dir, template_dir.tr(File::SEPARATOR, '_')) + "_#{template}"
              )
            end
          end
        end
      rescue IOError, Errno::ENOENT => e
        raise OptionsError, e.message
      end
    end
  end
end
