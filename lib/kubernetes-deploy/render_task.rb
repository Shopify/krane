# frozen_string_literal: true
require 'tempfile'

require 'kubernetes-deploy/renderer'

module KubernetesDeploy
  class RenderTask
    def initialize(logger:, current_sha:, template_dir:, bindings:)
      @logger = logger
      @template_dir = template_dir
      @renderer = KubernetesDeploy::Renderer.new(
        current_sha: current_sha,
        bindings: bindings,
        template_dir: @template_dir,
        logger: @logger,
      )
    end

    def run(*args)
      run!(*args)
      true
    rescue KubernetesDeploy::InvalidTemplateError, KubernetesDeploy::TaskConfigurationError
      false
    end

    def run!(filename, stream)
      validate_configuration(filename)
      file_content = File.read(File.join(@template_dir, filename))
      rendered_content = @renderer.render_template(filename, file_content)
      YAML.load_stream(rendered_content) do |doc|
        stream.puts YAML.dump(doc)
      end
      @logger.info("Rendered #{filename}")
      @logger.print_summary(:success)
    rescue KubernetesDeploy::InvalidTemplateError => exception
      log_invalid_template(filename, exception)
      raise
    rescue Psych::SyntaxError => exception
      log_invalid_template(filename, exception)
      raise InvalidTemplateError.new("Template is not valid YAML", filename: filename)
    rescue KubernetesDeploy::FatalDeploymentError
      @logger.print_summary(:failure)
      raise
    end

    private

    def validate_configuration(filename)
      @logger.info("Validating configuration")
      errors = []

      if filename.blank?
        errors << "Template can't be blank"
      end

      unless errors.empty?
        @logger.summary.add_action("Configuration invalid")
        @logger.summary.add_paragraph(errors.map { |err| "- #{err}" }.join("\n"))
        raise KubernetesDeploy::TaskConfigurationError, "Configuration invalid: #{errors.join(', ')}"
      end
    end

    def log_invalid_template(filename, exception)
      debug_msg = ColorizedString.new("Invalid template: #{filename}\n").red
      debug_msg += "Error message: #{exception}"
      @logger.summary.add_paragraph(debug_msg)
      @logger.print_summary(:failure)
    end
  end
end
