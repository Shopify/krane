# frozen_string_literal: true

require 'krane'
require 'thor'
require 'krane/cli/version_command'

module Krane
  module CLI
    class Krane < Thor
      include VersionCommand
      package_name "Krane"

      def self.exit_on_failure?
        true
      end

      private

      def logger(verbose: false)
        @logger ||= KubernetesDeploy::FormattedLogger.build(@namespace, @context, verbose_prefix: verbose)
      end
    end
  end
end
