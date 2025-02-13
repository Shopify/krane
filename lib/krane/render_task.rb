# frozen_string_literal: true
require 'tempfile'

require 'krane/common'
require 'krane/renderer'
require 'krane/template_sets'

module Krane
  # Render templates
  class RenderTask
    # Initializes the render task
    #
    # @param logger [Object] Logger object (defaults to an instance of Krane::FormattedLogger)
    # @param current_sha [String] The SHA of the commit
    # @param filenames [Array<String>] An array of filenames and/or directories containing templates (*required*)
    # @param bindings [Hash] Bindings parsed by Krane::BindingsParser
    def initialize(logger: nil, current_sha:, filenames: [], bindings:)
      @logger = logger || Krane::FormattedLogger.build
      @filenames = filenames.map { |path| File.expand_path(path) }
      @bindings = bindings
      @current_sha = current_sha
    end

    # Runs the task, returning a boolean representing success or failure
    #
    # @return [Boolean]
    def run(**args)
      run!(**args)
      true
    rescue Krane::FatalDeploymentError
      false
    end

    # Runs the task, raising exceptions in case of issues
    #
    # @param stream [IO] Place to stream the output to
    #
    # @return [nil]
    def run!(stream:)
      @logger.reset
      @logger.phase_heading("Initializing render task")

      ts = TemplateSets.from_dirs_and_files(paths: @filenames, logger: @logger)

      validate_configuration(ts)
      count = render_templates(stream, ts)

      @logger.summary.add_action("Successfully rendered #{count} template(s)")
      @logger.print_summary(:success)
    rescue Krane::FatalDeploymentError
      @logger.print_summary(:failure)
      raise
    end

    private

    def render_templates(stream, template_sets)
      @logger.phase_heading("Rendering template(s)")
      count = 0
      template_sets.with_resource_definitions_and_filename(current_sha: @current_sha,
        bindings: @bindings, raw: true) do |rendered_content, filename|
        write_to_stream(rendered_content, filename, stream)
        count += 1
      end

      count
    rescue Krane::InvalidTemplateError => exception
      log_invalid_template(exception)
      raise
    end

    def write_to_stream(rendered_content, filename, stream)
      file_basename = File.basename(filename)
      @logger.info("Rendering #{file_basename}...")
      implicit = []
      YAML.parse_stream(rendered_content, filename: "<rendered> #{filename}") { |d| implicit << d.implicit }
      if rendered_content.present?
        stream.puts "---\n" if implicit.first
        stream.puts rendered_content
        @logger.info("Rendered #{file_basename}")
      else
        @logger.warn("Rendered #{file_basename} successfully, but the result was blank")
      end
    rescue Psych::SyntaxError => exception
      raise InvalidTemplateError.new("Template is not valid YAML. #{exception.message}", filename: filename)
    end

    def validate_configuration(template_sets)
      @logger.info("Validating configuration")
      errors = []
      if @filenames.blank?
        errors << "filenames must be set"
      end

      if !@current_sha.nil? && @current_sha.empty?
        errors << "`current-sha is optional but can not be blank"
      end
      errors += template_sets.validate

      unless errors.empty?
        @logger.summary.add_action("Configuration invalid")
        @logger.summary.add_paragraph(errors.map { |err| "- #{err}" }.join("\n"))
        raise Krane::TaskConfigurationError, "Configuration invalid: #{errors.join(', ')}"
      end
    end

    def log_invalid_template(exception)
      @logger.error("Failed to render #{exception.filename}")

      debug_msg = ColorizedString.new("Invalid template: #{exception.filename}\n").red
      debug_msg += "> Error message:\n#{FormattedLogger.indent_four(exception.to_s)}"
      if exception.content
        debug_msg += "\n> Template content:\n#{FormattedLogger.indent_four(exception.content)}"
      end
      @logger.summary.add_paragraph(debug_msg)
    end
  end
end
