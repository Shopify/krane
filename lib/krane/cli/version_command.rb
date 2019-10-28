# frozen_string_literal: true

module Krane
  module CLI
    class VersionCommand
      OPTIONS = {}

      def self.from_options(_)
        puts("krane #{::Krane::VERSION}")
      end
    end
  end
end
