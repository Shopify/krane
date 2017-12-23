# frozen_string_literal: true

module KubernetesDeploy
  ##
  # This class is a less strict extension of ActiveSupport::Duration::ISO8601Parser.
  # In addition to full ISO8601 durations, it can parse unprefixed ISO8601 time components (e.g. '1H').
  # It is also case-insensitive.
  # For example, this class considers the values "1H", "1h" and "PT1H" to be valid and equivalent.

  class DurationParser
    class ParsingError < ArgumentError; end

    def initialize(value)
      @iso8601_str = value.to_s.strip.upcase
    end

    def parse!
      if @iso8601_str.blank?
        raise ParsingError, "Cannot parse blank value"
      end

      parser = ActiveSupport::Duration::ISO8601Parser.new(@iso8601_str)
      parser.mode = :time unless @iso8601_str.start_with?("P")
      parts = parser.parse!
      ActiveSupport::Duration.new(calculate_total_seconds(parts), parts)
    rescue ActiveSupport::Duration::ISO8601Parser::ParsingError => e
      raise ParsingError, e.message
    end

    private

    # https://github.com/rails/rails/blob/19c450d5d99275924254b2041b6ad470fdaa1f93/activesupport/lib/active_support/duration.rb#L79-L83
    def calculate_total_seconds(parts)
      parts.inject(0) do |total, (part, value)|
        total + value * ActiveSupport::Duration::PARTS_IN_SECONDS[part]
      end
    end
  end
end
