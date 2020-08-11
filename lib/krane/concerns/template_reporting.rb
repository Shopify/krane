# frozen_string_literal: true

module Krane
  module TemplateReporting
    def record_invalid_template(logger:, err:, filename:, content: nil)
      debug_msg = ColorizedString.new("Invalid template: #{filename}\n").red
      debug_msg += "> Error message:\n#{Krane::FormattedLogger.indent_four(err)}"
      if content
        debug_msg += if content =~ /kind:\s*Secret/
          "\n> Template content: Suppressed because it may contain a Secret"
        else
          "\n> Template content:\n#{Krane::FormattedLogger.indent_four(content)}"
        end
      end
      logger.summary.add_paragraph(debug_msg)
    end

    def add_para_from_list(logger:, action:, enum:)
      logger.summary.add_action(action)
      logger.summary.add_paragraph(enum.map { |e| "- #{e}" }.join("\n"))
    end
  end
end
