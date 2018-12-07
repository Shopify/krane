# frozen_string_literal: true
require 'tempfile'

require 'kubernetes-deploy/renderer'
require 'kubernetes-deploy/template_discovery'

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
    rescue KubernetesDeploy::FatalDeploymentError
      false
    end

    def run!(stream, only_filenames = [])
      @logger.reset
      @logger.phase_heading("Initializing render task")

      filenames = if only_filenames.empty?
        TemplateDiscovery.new(@template_dir).templates
      else
        only_filenames
      end

      validate_configuration(filenames)
      @logger.phase_heading("Rendering template(s)")

      filenames.each { |filename| render_filename(filename, stream) }

      @logger.summary.add_action("Successfully rendered #{filenames.size} template(s)")
      @logger.print_summary(:success)
    rescue KubernetesDeploy::FatalDeploymentError
      @logger.print_summary(:failure)
      raise
    end

    private

    def render_filename(filename, stream)
      file_content = File.read(File.join(@template_dir, filename))
      rendered_content = @renderer.render_template(filename, file_content)
      YAML.load_stream(rendered_content, "<rendered> #{filename}") do |doc|
        stream.puts YAML.dump(doc)
      end
      @logger.info("Rendered #{File.basename(filename)}")

    rescue KubernetesDeploy::InvalidTemplateError => exception
      log_invalid_template(filename, exception)
      raise
    rescue Psych::SyntaxError => exception
      log_invalid_template(filename, exception)
      raise InvalidTemplateError.new("Template is not valid YAML", filename: filename)
    end

    def validate_configuration(filenames)
      @logger.info("Validating configuration")
      errors = []

      if filenames.empty?
        errors << "no templates found in template dir #{@template_dir}"
      end

      absolute_template_dir = File.expand_path(@template_dir)

      filenames.each do |filename|
        absolute_file = File.expand_path(File.join(@template_dir, filename))
        if !File.exist?(absolute_file)
          errors << "Filename \"#{absolute_file}\" could not be found"
        elsif !File.file?(absolute_file)
          errors << "Filename \"#{absolute_file}\" is not a file"
        elsif !absolute_file.start_with?(absolute_template_dir)
          errors << "Filename \"#{absolute_file}\" is outside the template directory"
        end
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
    end
  end
end
