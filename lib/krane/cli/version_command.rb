# frozen_string_literal: true
require 'active_support/concern'

module Krane
  module CLI
    module VersionCommand
      extend ActiveSupport::Concern

      included do
        desc "version", "Prints the version"
        def version
          logger.info("Krane Version: #{KubernetesDeploy::VERSION}")
        end
      end
    end
  end
end
