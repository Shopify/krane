# frozen_string_literal: true

require 'active_support/duration'

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
      ActiveSupport::Duration.parse("PT#{@iso8601_str}") # By default assume it is just a time component
    rescue ActiveSupport::Duration::ISO8601Parser::ParsingError
      begin
        ActiveSupport::Duration.parse(@iso8601_str)
      rescue ActiveSupport::Duration::ISO8601Parser::ParsingError => e
        raise ParsingError, e.message
      end
    end
  end
end
