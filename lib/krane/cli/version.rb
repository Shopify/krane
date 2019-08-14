# frozen_string_literal: true

module Krane
  class CLI
    desc "version", "Prints the version"
    def version
      logger.info("Krane Version: #{KubernetesDeploy::VERSION}")
    end
  end
end
