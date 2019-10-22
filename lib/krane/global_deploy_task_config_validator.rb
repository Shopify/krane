# frozen_string_literal: true

require 'krane/task_config_validator'

module Krane
  class GlobalDeployTaskConfigValidator < Krane::TaskConfigValidator
    def initialize(*arguments)
      super(*arguments)
      @validations -= [:validate_namespace_exists]
    end

    def validate_resources(resources, selector)
      validate_globals(resources)

      Krane::Concurrency.split_across_threads(resources) do |r|
        r.validate_definition(@kubectl, selector: selector)
      end

      resources.select(&:has_warnings?).each do |resource|
        record_warnings(logger: logger, warning: resource.validation_warning_msg,
          filename: File.basename(resource.file_path))
      end

      failed_resources = resources.select(&:validation_failed?)
      if failed_resources.present?
        failed_resources.each do |r|
          content = File.read(r.file_path) if File.file?(r.file_path) && !r.sensitive_template_content?
          record_invalid_template(logger: logger, err: r.validation_error_msg,
            filename: File.basename(r.file_path), content: content)
        end
        raise Krane::FatalDeploymentError, "Template validation failed"
      end
    end

    private

    def validate_globals(resources)
      return unless (namespaced = resources.reject(&:global?).presence)
      namespaced_names = namespaced.map do |resource|
        "#{resource.name} (#{resource.type}) in #{File.basename(resource.file_path)}"
      end
      namespaced_names = ::Krane::FormattedLogger.indent_four(namespaced_names.join("\n"))

      logger.summary.add_paragraph(ColorizedString.new("Namespaced resources:\n#{namespaced_names}").yellow)
      raise ::Krane::FatalDeploymentError, "Deploying namespaced resource is not allowed from this command."
    end
  end
end
