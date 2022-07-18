# frozen_string_literal: true

module Krane
  class Node
    attr_reader :name

    class << self
      def group
        ""
      end

      def kind
        name.demodulize
      end
    end

    def initialize(definition:)
      @name = definition.dig("metadata", "name").to_s
      @definition = definition
    end
  end
end
