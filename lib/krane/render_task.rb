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
    # @param logger [Object] Logger object (defaults to an instance of KubernetesDeploy::FormattedLogger)
    # @param current_sha [String] The SHA of the commit
    # @param template_dir [String] Path to a directory with templates to render (deprecated)
    # @param template_paths [Array<String>] An array of template paths to render
    # @param bindings [Hash] Bindings parsed by KubernetesDeploy::BindingsParser
    def initialize(logger: nil, current_sha:, template_dir: nil, template_paths: [], bindings:)
      @logger = logger || KubernetesDeploy::FormattedLogger.build
      @template_dir = template_dir
      @template_paths = template_paths.map { |path| File.expand_path(path) }
      @bindings = bindings
      @current_sha = current_sha
    end

    # Runs the task, returning a boolean representing success or failure
    #
    # @return [Boolean]
    def run(*args)
      run!(*args)
      true
    rescue KubernetesDeploy::FatalDeploymentError
      false
    end

    # Runs the task, raising exceptions in case of issues
    #
    # @param stream [IO] Place to stream the output to
    # @param only_filenames [Array<String>] List of filenames to render
    #
    # @return [nil]
    def run!(stream, only_filenames = [])
      @logger.reset
      @logger.phase_heading("Initializing render task")

      ts = TemplateSets.from_dirs_and_files(paths: template_sets_paths(only_filenames), logger: @logger)

      validate_configuration(ts, only_filenames)
      count = render_templates(stream, ts)

      @logger.summary.add_action("Successfully rendered #{count} template(s)")
      @logger.print_summary(:success)
    rescue KubernetesDeploy::FatalDeploymentError
      @logger.print_summary(:failure)
      raise
    end

    private

    def template_sets_paths(only_filenames)
      if @template_paths.present?
        # Validation will catch @template_paths & @template_dir being present
        @template_paths
      elsif only_filenames.blank?
        [File.expand_path(@template_dir || '')]
      else
        absolute_template_dir = File.expand_path(@template_dir || '')
        only_filenames.map do |name|
          File.join(absolute_template_dir, name)
        end
      end
    end

    def render_templates(stream, template_sets)
      @logger.phase_heading("Rendering template(s)")
      count = 0
      template_sets.with_resource_definitions_and_filename(render_erb: true,
          current_sha: @current_sha, bindings: @bindings, raw: true) do |rendered_content, filename|
        write_to_stream(rendered_content, filename, stream)
        count += 1
      end

      count
    rescue KubernetesDeploy::InvalidTemplateError => exception
      log_invalid_template(exception)
      raise
    end

    def write_to_stream(rendered_content, filename, stream)
      file_basename = File.basename(filename)
      @logger.info("Rendering #{file_basename}...")
      implicit = []
      YAML.parse_stream(rendered_content, "<rendered> #{filename}") { |d| implicit << d.implicit }
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

    def validate_configuration(template_sets, filenames)
      @logger.info("Validating configuration")
      errors = []
      if @template_dir.present? && @template_paths.present?
        errors << "template_dir and template_paths can not be combined"
      elsif @template_dir.blank? && @template_paths.blank?
        errors << "template_dir or template_paths must be set"
      end

      if filenames.present?
        if @template_dir.nil?
          errors << "template_dir must be set to use filenames"
        else
          absolute_template_dir = File.expand_path(@template_dir)
          filenames.each do |filename|
            absolute_file = File.expand_path(File.join(@template_dir, filename))
            unless absolute_file.start_with?(absolute_template_dir)
              errors << "Filename \"#{absolute_file}\" is outside the template directory," \
              " which was resolved as #{absolute_template_dir}"
            end
          end
        end
      end

      errors += template_sets.validate

      unless errors.empty?
        @logger.summary.add_action("Configuration invalid")
        @logger.summary.add_paragraph(errors.map { |err| "- #{err}" }.join("\n"))
        raise KubernetesDeploy::TaskConfigurationError, "Configuration invalid: #{errors.join(', ')}"
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
