# frozen_string_literal: true
require 'tempfile'

require 'krane/common'
require 'krane/template_sets'

module Krane
  # Annotate templates
  class AnnotateTask
    POD_CONTROLLER_RESOURCES = ['deployment', 'replicaset', 'statefulset', 'daemonset']

    # Initializes the annotate task
    #
    # @param logger [Object] Logger object (defaults to an instance of Krane::FormattedLogger)
    # @param current_sha [String] The SHA of the commit
    # @param filenames [Array<String>] An array of filenames and/or directories containing templates (*required*)
    # @param bindings [Hash] Bindings parsed by Krane::BindingsParser
    def initialize(logger: nil, filenames: [], resources:, annotations:)
      @logger = logger || Krane::FormattedLogger.build
      @filenames = filenames.map { |path| File.expand_path(path) }
      @resources = resources
      @annotations = annotations
    end

    # Runs the task, returning a boolean representing success or failure
    #
    # @return [Boolean]
    def run(*args)
      run!(*args)
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
      @logger.phase_heading("Initializing annotate task")

      ts = TemplateSets.from_dirs_and_files(paths: @filenames, logger: @logger, render_erb: false)

      validate_configuration(ts)
      count = add_annotations(stream, ts)

      @logger.summary.add_action("Successfully annotated #{count} template(s)")
      @logger.print_summary(:success)
    rescue Krane::FatalDeploymentError
      @logger.print_summary(:failure)
      raise
    end

    private

    def add_annotations(stream, template_sets)
      @logger.phase_heading("Adding annotation(s)")
      annotated_resources = []
      template_sets.with_resource_definitions_and_filename() do |content, filename|
        annotated_resources.concat(inject_annotations(stream, filename, content))
      end

      unannotated_resources = @resources - annotated_resources
      @logger.warn("Couldn't find and annotate `#{unannotated_resources.join(',')}` resource(s)") if unannotated_resources.size > 0

      annotated_resources.size
    end

    def inject_annotations(stream, filename, content)
      file_basename = File.basename(filename)
      annotated_resources = []

      if @resources.empty? || @resources.include?(content['kind'].downcase)
        content['metadata'].has_key?('annotations') ? nil : content['metadata']['annotations'] = {}
        content['metadata']['annotations'].merge!(@annotations)
        
        annotated_resources << content['kind'].downcase
        @logger.info("Annotated #{content['kind']} resource")
      end

      if (@resources.include?('pod') || @resources.empty?) && POD_CONTROLLER_RESOURCES.include?(content['kind'].downcase)
        content['spec']['template']['metadata'].has_key?('annotations') ? nil : content['spec']['template']['metadata']['annotations'] = {}
        content['spec']['template']['metadata']['annotations'].merge!(@annotations)

        annotated_resources << 'pod'
        @logger.info("Annotated pod resource defined in #{content['kind']} resource")
      end

      stream.puts content
      annotated_resources
    end

    def validate_configuration(template_sets)
      @logger.info("Validating configuration")
      errors = []
      if @filenames.blank?
        errors << "filenames must be set"
      end

      errors += template_sets.validate

      unless errors.empty?
        @logger.summary.add_action("Configuration invalid")
        @logger.summary.add_paragraph(errors.map { |err| "- #{err}" }.join("\n"))
        raise Krane::TaskConfigurationError, "Configuration invalid: #{errors.join(', ')}"
      end
    end
  end
end
