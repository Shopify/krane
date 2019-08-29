# frozen_string_literal: true
require 'kubernetes-deploy/template_set'

module KubernetesDeploy
  class TemplateSets
    VALID_TEMPLATES = %w(.yml.erb .yml .yaml .yaml.erb)
    class << self
      def new_from_dirs_and_files(dirs_and_files, logger:, current_sha:, bindings:)
        resource_templates = {}
        dir_paths, file_paths = dirs_and_files.partition { |path| File.directory?(path) }

        # Directory paths
        dir_paths.each_with_object(resource_templates) do |template_dir, hash|
          hash[template_dir] = Dir.foreach(template_dir).select do |filename|
            filename.end_with?(*VALID_TEMPLATES) || filename == EjsonSecretProvisioner::EJSON_SECRETS_FILE
          end
        end
        # Filename paths
        file_paths.each_with_object(resource_templates) do |filename, hash|
          dir_name = File.dirname(filename)
          hash[dir_name] ||= []
          hash[dir_name] << File.basename(filename) unless hash[dir_name].include?(filename)
        end

        template_sets = TemplateSets.new
        resource_templates.map do |path, files|
          template_sets << TemplateSet.new(template_dir: path, file_whitelist: files, logger: logger,
              renderer: Renderer.new(
                current_sha: current_sha,
                logger: logger,
                bindings: bindings,
                template_dir: path
              ))
        end
        template_sets
      end
    end

		def <<(template_set)
			if template_set.is_a?(TemplateSet)
				@template_sets << template_set
			else
				raise InvalidTemplateError, "Expected TemplateSet but got #{template_set.class}"
			end
    end

    def with_resource_definitions(render_erb: false)
      @template_sets.flat_map do |template_set|
        template_set.with_resource_definitions(render_erb: render_erb) do |r_def|
          yield r_def
        end
      end
    end

    def ejson_secrets_files
      @template_sets.map(&:ejson_secrets_file).compact
    end

    def validate
      errors = []
      @template_sets.each do |template_set|
        errors << template_set.validate
      end
      errors.flatten
    end

    private

    def initialize
      @template_sets = []
    end
  end
end
