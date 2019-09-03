# frozen_string_literal: true

module KubernetesDeploy
  class TemplateSets
    VALID_TEMPLATES = %w(.yml.erb .yml .yaml .yaml.erb)
    # private inner class
    class TemplateSet
      def initialize(template_dir:, file_whitelist: [], logger:)
        @template_dir = template_dir
        @files = file_whitelist
        @logger = logger
      end

      def with_resource_definitions(render_erb: false, current_sha: nil, bindings: nil)
        if render_erb
          @renderer = Renderer.new(
            template_dir: @template_dir,
            logger: @logger,
            current_sha: current_sha,
            bindings: bindings,
          )
        end
        @files.each do |filename|
          next if filename.end_with?(EjsonSecretProvisioner::EJSON_SECRETS_FILE)
          templates(filename: filename) do |r_def|
            yield r_def
          end
        end
      end

      def ejson_secrets_file
        @ejson_secrets_file ||= begin
          secret_file = @files.find { |f| f == EjsonSecretProvisioner::EJSON_SECRETS_FILE }
          File.join(@template_dir, secret_file) if secret_file
        end
      end

      def validate
        errors = []
        if Dir.entries(@template_dir).none? do |filename|
             filename.end_with?(*TemplateSets::VALID_TEMPLATES) ||
             filename.end_with?(EjsonSecretProvisioner::EJSON_SECRETS_FILE)
           end
          return errors << "Template directory #{@template_dir} does not contain any valid templates"
        end

        @files.each do |filename|
          filename = File.join(@template_dir, filename)
          if !File.exist?(filename)
            errors << "File #{filename} does not exist"
          elsif !filename.end_with?(*TemplateSets::VALID_TEMPLATES) &&
                !filename.end_with?(EjsonSecretProvisioner::EJSON_SECRETS_FILE)
            errors << "File #{filename} does not have valid suffix (supported suffixes: " \
              "#{TemplateSets::VALID_TEMPLATES.join(', ')}, or #{EjsonSecretProvisioner::EJSON_SECRETS_FILE})"
          end
        end
        errors
      end

      private

      def templates(filename:)
        file_content = File.read(File.join(@template_dir, filename))
        rendered_content = @renderer ? @renderer.render_template(filename, file_content) : file_content
        YAML.load_stream(rendered_content, "<rendered> #{filename}") do |doc|
          next if doc.blank?
          unless doc.is_a?(Hash)
            raise InvalidTemplateError.new("Template is not a valid Kubernetes manifest",
              filename: filename, content: doc)
          end
          yield doc
        end
      rescue InvalidTemplateError => err
        err.filename ||= filename
        raise err
      rescue Psych::SyntaxError => err
        raise InvalidTemplateError.new(err.message, filename: filename, content: rendered_content)
      end
    end
    private_constant :TemplateSet

    class << self
      def from_dirs_and_files(paths:, logger:)
        resource_templates = {}
        dir_paths, file_paths = paths.partition { |path| File.directory?(path) }

        # Directory paths
        dir_paths.each do |template_dir|
          resource_templates[template_dir] = Dir.foreach(template_dir).select do |filename|
            filename.end_with?(*VALID_TEMPLATES) || filename == EjsonSecretProvisioner::EJSON_SECRETS_FILE
          end
        end

        # Filename paths
        file_paths.each do |filename|
          dir_name = File.dirname(filename)
          resource_templates[dir_name] ||= []
          resource_templates[dir_name] << File.basename(filename) unless resource_templates[dir_name].include?(filename)
        end

        template_sets = []
        resource_templates.each do |template_dir, files|
          template_sets << TemplateSet.new(template_dir: template_dir, file_whitelist: files, logger: logger)
        end
        TemplateSets.new(template_sets: template_sets)
      end
    end

    def with_resource_definitions(render_erb: false, current_sha: nil, bindings: nil)
      @template_sets.each do |template_set|
        template_set.with_resource_definitions(
          render_erb: render_erb,
          current_sha: current_sha,
          bindings: bindings
        ) do |r_def|
          yield r_def
        end
      end
    end

    def ejson_secrets_files
      @template_sets.map(&:ejson_secrets_file).compact
    end

    def validate
      @template_sets.flat_map(&:validate)
    end

    private

    def initialize(template_sets: [])
      @template_sets = template_sets
    end
  end
end
