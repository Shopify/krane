# frozen_string_literal: true

module KubernetesDeploy
  class TemplateSet
    def initialize(template_dir:, file_whitelist: [], logger:, renderer:)
      @template_dir = template_dir
      @files = file_whitelist
      @logger = logger
      @renderer = renderer
    end

    def with_resource_definitions(render_erb: false)
      @files.each do |filename|
        next if filename.end_with?(EjsonSecretProvisioner::EJSON_SECRETS_FILE)
        templates(filename: filename, render_erb: render_erb) do |r_def|
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
           filename.end_with?(*TemplateSets::VALID_TEMPLATES) || EjsonSecretProvisioner::EJSON_SECRETS_FILE
         end
        return errors << "Template directory #{@template_dir} does not contain any valid templates"
      end
      @files.each do |filename|
        filename = File.join(@template_dir, filename)
        unless File.exist?(filename)
          errors << "File #{filename} does not exist"
        end
      end
      errors
    end

    private

    def templates(filename:, render_erb: false)
      file_content = File.read(File.join(@template_dir, filename))
      rendered_content = render_erb ? @renderer.render_template(filename, file_content) : file_content
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
end
