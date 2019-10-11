# frozen_string_literal: true
require 'colorized_string'

module KubernetesDeploy
  # Adds the methods kubernetes-deploy requires to your logger class.
  # These methods include helpers for logging consistent headings, as well as facilities for
  # displaying key information later, in a summary section, rather than when it occurred.
  module DeferredSummaryLogging
    attr_reader :summary
    def initialize(*args)
      reset
      super
    end

    def reset
      @summary = DeferredSummary.new
      @current_phase = 0
    end

    def blank_line(level = :info)
      public_send(level, "")
    end

    def phase_heading(phase_name)
      @current_phase += 1
      heading("Phase #{@current_phase}: #{phase_name}")
    end

    def heading(text, secondary_msg = '', secondary_msg_color = :cyan)
      padding = (100.0 - (text.length + secondary_msg.length)) / 2
      blank_line
      part1 = ColorizedString.new("#{'-' * padding.floor}#{text}").cyan
      part2 = ColorizedString.new(secondary_msg).colorize(secondary_msg_color)
      part3 = ColorizedString.new('-' * padding.ceil).cyan
      info(part1 + part2 + part3)
    end

    # Outputs the deferred summary information saved via @logger.summary.add_action and @logger.summary.add_paragraph
    def print_summary(status)
      status_string = status.to_s.humanize.upcase
      if status == :success
        heading("Result: ", status_string, :green)
        level = :info
      elsif status == :timed_out
        heading("Result: ", status_string, :yellow)
        level = :fatal
      else
        heading("Result: ", status_string, :red)
        level = :fatal
      end

      if (actions_sentence = summary.actions_sentence.presence)
        public_send(level, actions_sentence)
        blank_line(level)
      end

      summary.paragraphs.each do |para|
        msg_lines = para.split("\n")
        msg_lines.each { |line| public_send(level, line) }
        blank_line(level) unless para == summary.paragraphs.last
      end
    end

    class DeferredSummary
      attr_reader :paragraphs

      def initialize
        @actions_taken = []
        @paragraphs = []
      end

      def actions_sentence
        return unless @actions_taken.present?
        @actions_taken.to_sentence.capitalize
      end

      # Saves a sentence fragment to be displayed in the first sentence of the summary section
      #
      # Example:
      # # The resulting summary will begin with "Created 3 secrets and failed to deploy 2 resources"
      # @logger.summary.add_action("created 3 secrets")
      # @logger.summary.add_action("failed to deploy 2 resources")
      def add_action(sentence_fragment)
        @actions_taken << sentence_fragment
      end

      # Adds a paragraph to be displayed in the summary section
      # Paragraphs will be printed in the order they were added, separated by a blank line
      # This can be used to log a block of data on a particular topic, e.g. debug info for a particular failed resource
      def add_paragraph(paragraph)
        paragraphs << paragraph
      end
    end
  end
end
