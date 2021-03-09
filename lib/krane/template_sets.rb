# frozen_string_literal: true
require 'open3'
require 'krane/delayed_exceptions'
require 'krane/ejson_secret_provisioner'

module Krane
  class TemplateSets
    include DelayedExceptions
    VALID_TEMPLATES = %w(.yml.erb .yml .yaml .yaml.erb)
    # private inner class
    class TemplateSet
      include DelayedExceptions
      attr_reader :render_erb
      def initialize(template_dir:, file_whitelist: [], logger:, render_erb: true)
        @template_dir = template_dir
        @files = file_whitelist
        @logger = logger
        @render_erb = render_erb
      end

      def with_resource_definitions_and_filename(current_sha: nil, bindings: nil, raw: false)
        if @render_erb
          @renderer = Renderer.new(
            template_dir: @template_dir,
            logger: @logger,
            current_sha: current_sha,
            bindings: bindings,
          )
        end
        with_delayed_exceptions(@files, Krane::InvalidTemplateError) do |filename|
          next if filename.end_with?(EjsonSecretProvisioner::EJSON_SECRETS_FILE)
          templates(filename: filename, raw: raw) { |r_def| yield r_def, filename }
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
        supported_extensions = if @render_erb
          TemplateSets::VALID_TEMPLATES
        else
          TemplateSets::VALID_TEMPLATES.reject { |extension| extension.include?('erb') }
        end

        if Dir.entries(@template_dir).none? do |filename|
             filename.end_with?(*supported_extensions) ||
             filename.end_with?(EjsonSecretProvisioner::EJSON_SECRETS_FILE)
           end
          return errors << "Template directory #{@template_dir} does not contain any valid templates (supported " \
              "suffixes: #{supported_extensions.join(', ')}, or #{EjsonSecretProvisioner::EJSON_SECRETS_FILE})"
        end

        @files.each do |filename|
          filename = File.join(@template_dir, filename)
          if !File.exist?(filename)
            errors << "File #{filename} does not exist"
          elsif !filename.end_with?(*supported_extensions) &&
                !filename.end_with?(EjsonSecretProvisioner::EJSON_SECRETS_FILE)
            errors << "File #{filename} does not have valid suffix (supported suffixes: " \
              "#{supported_extensions.join(', ')}, or #{EjsonSecretProvisioner::EJSON_SECRETS_FILE})"
          end
        end
        errors
      end

      def deploying_with_erb_files?
        @files.any? { |file| file.end_with?("erb") }
      end

      private

      def templates(filename:, raw:)
        file_content = File.read(File.join(@template_dir, filename))
        rendered_content = @renderer ? @renderer.render_template(filename, file_content) : file_content
        YAML.load_stream(rendered_content, "<rendered> #{filename}") do |doc|
          next if doc.blank?
          unless doc.is_a?(Hash)
            raise InvalidTemplateError.new("Template is not a valid Kubernetes manifest", filename: filename, content: doc)
          end

          # If the YAML document is encrypted with SOPS, it will contain this `sops` key, which we can use to decrypt using the
          # `sops` binary installed on the system, with the expectation that it is installed and configured
          if doc["sops"].present?
           stdout, stderr, status = Open3.capture3("sops --input-type yaml --output-type yaml --decrypt /dev/stdin", stdin_data: doc.to_yaml)
            if status.success?
              @logger.summary.add_paragraph("Decrypted contents of #{filename} with SOPS")
              doc = YAML.safe_load(stdout)
            else
              raise InvalidTemplateError.new("Failed to decrypt contents of #{filename} with SOPS; ensure SOPS is installed and configured properly", filename: filename, content: doc)
            end
          end

          yield doc unless raw
        end
        yield rendered_content if raw
      rescue InvalidTemplateError => err
        err.filename ||= filename
        raise err
      rescue SystemCallError => err
        # Most common error here will be Errno::ENOENT (which can occur when SOPS is not installed)
        # Errors running the SOPS command are captured above using Open3
        raise InvalidTemplateError.new("Failed to decrypt contents of #{filename} with SOPS; ensure SOPS is installed and configured properly", filename: filename, content: doc)
      rescue Psych::SyntaxError => err
        raise InvalidTemplateError.new(err.message, filename: filename, content: rendered_content)
      end
    end
    private_constant :TemplateSet

    class << self
      def from_dirs_and_files(paths:, logger:, render_erb: true)
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
          template_sets << TemplateSet.new(template_dir: template_dir, file_whitelist: files, logger: logger,
            render_erb: render_erb)
        end
        TemplateSets.new(template_sets: template_sets)
      end
    end

    def with_resource_definitions_and_filename(current_sha: nil, bindings: nil, raw: false)
      with_delayed_exceptions(@template_sets, Krane::InvalidTemplateError) do |template_set|
        template_set.with_resource_definitions_and_filename(
          current_sha: current_sha,
          bindings: bindings,
          raw: raw
        ) do |r_def, filename|
          yield r_def, filename
        end
      end
    end

    def with_resource_definitions(current_sha: nil, bindings: nil, raw: false)
      with_resource_definitions_and_filename(current_sha: current_sha, bindings: bindings, raw: raw) do |r_def, _|
        yield r_def
      end
    end

    def ejson_secrets_files
      @template_sets.map(&:ejson_secrets_file).compact
    end

    def validate
      errors = @template_sets.flat_map(&:validate)

      if rendering_erb_disabled? && deploying_with_erb_files?
        errors << "ERB template discovered with rendering disabled. If you were trying to render ERB and " \
          "deploy the result, try piping the output of `krane render` to `krane-deploy -f -`"
      end

      errors
    end

    private

    def deploying_with_erb_files?
      @template_sets.any?(&:deploying_with_erb_files?)
    end

    def rendering_erb_disabled?
      !@template_sets.any?(&:render_erb)
    end

    def initialize(template_sets: [])
      @template_sets = template_sets
    end
  end
end
