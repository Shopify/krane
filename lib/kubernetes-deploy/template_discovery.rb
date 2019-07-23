# frozen_string_literal: true
module KubernetesDeploy
  class TemplateDiscovery
    VALID_EXTENSIONS = %w(.yml.erb .yml .yaml .yaml.erb)

    class << self
      def validate_templates(template_paths)
        file_regex = /(\.ya?ml(\.erb)?)$|(secrets\.ejson)$/
        errors = []
        template_paths.each do |path|
          if !File.directory?(path) && !File.file?(path)
            errors << "Template does not exist. Couldn't find file or directory #{path}"
          elsif File.directory?(path) && Dir.entries(path).none? { |file| file =~ file_regex }
            errors << "`#{path}` doesn't contain valid templates (secrets.ejson or postfix .yml, .yml.erb)"
          end
        end
        errors
      end

      def resource_templates(template_paths)
        resource_templates = {}
        dir_paths = template_paths.select { |path| File.directory?(path) }
        file_paths = template_paths.select { |path| File.file?(path) && path.end_with?(*VALID_EXTENSIONS) }

        # Directory paths
        dir_paths.each_with_object(resource_templates) do |template_dir, hash|
          hash[template_dir] = Dir.foreach(template_dir).select do |filename|
            filename.end_with?(*VALID_EXTENSIONS)
          end
        end
        # Filename paths
        file_paths.each_with_object(resource_templates) do |filename, hash|
          dir_name = File.dirname(filename)
          hash[dir_name] ||= []
          hash[dir_name] << File.basename(filename) unless hash[dir_name].include?(filename)
        end

        resource_templates
      end

      def ejson_secret_templates(template_paths)
        ejson_secrets_filename = KubernetesDeploy::EjsonSecretProvisioner::EJSON_SECRETS_FILE

        template_paths.each_with_object([]) do |path, secrets|
          if File.directory?(path) && Dir.entries(path).include?(ejson_secrets_filename)
            secrets << File.expand_path(File.join(path, ejson_secrets_filename))
          elsif File.basename(path) == ejson_secrets_filename
            secrets << File.expand_path(path)
          end
        end
      end
    end
  end
end
