# frozen_string_literal: true

require 'thor'

module Krane
  class CLI < Thor
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
