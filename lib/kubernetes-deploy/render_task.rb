# frozen_string_literal: true
require 'tempfile'

require 'kubernetes-deploy/common'
require 'kubernetes-deploy/renderer'
require 'kubernetes-deploy/template_sets'

module KubernetesDeploy
  class RenderTask
    def initialize(logger: nil, current_sha:, template_dir: nil, template_paths: [], bindings:)
      @logger = logger || KubernetesDeploy::FormattedLogger.build
      @template_dir = template_dir
      @template_paths = template_paths.map { |path| File.expand_path(path) }
      @bindings = bindings
      @current_sha = current_sha
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
      exceptions = []
      @logger.phase_heading("Rendering template(s)")
      count = 0
      begin
        template_sets.with_resource_definitions_and_filename(render_erb: true,
            current_sha: @current_sha, bindings: @bindings, raw: true) do |rendered_content, filename|
          render_filename(rendered_content, filename, stream)
          count += 1
        end
      rescue KubernetesDeploy::InvalidTemplateError => exception
        exceptions << exception
        log_invalid_template(exception)
      end

      unless exceptions.empty?
        raise exceptions[0]
      end
      count
    end

    def render_filename(rendered_content, filename, stream)
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
