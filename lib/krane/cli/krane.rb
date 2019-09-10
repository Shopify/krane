# frozen_string_literal: true

require 'krane'
require 'thor'
require 'krane/cli/version_command'

module Krane
  module CLI
    class Krane < Thor
      package_name "Krane"

      def self.expand_options(task_options)
        task_options.each { |option_name, config| method_option(option_name, config) }
      end

      desc("version", "Prints the version")
      expand_options(VersionCommand::OPTIONS)
      def version
        VersionCommand.from_options(options)
      end

      def self.exit_on_failure?
        true
      end
    end
  end
end
