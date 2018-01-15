# frozen_string_literal: true
module KubernetesDeploy
  class FatalDeploymentError < StandardError; end
  class KubectlError < StandardError; end

  class NamespaceNotFoundError < FatalDeploymentError
    def initialize(name, context)
      super("Namespace `#{name}` not found in context `#{context}`")
    end
  end
  class Errors
    def self.server_version_warning(server_version, logger)
      if server_version < Gem::Version.new(MIN_KUBE_VERSION)
        logger.warn("Minimum cluster version requirement of #{MIN_KUBE_VERSION} not met. "\
        "Using #{server_version} could result in unexpected behavior as it is no longer tested against")
      end
    end
  end
end
