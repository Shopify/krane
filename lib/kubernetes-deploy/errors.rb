# frozen_string_literal: true
module KubernetesDeploy
  class FatalDeploymentError < StandardError; end
  class KubectlError < StandardError; end

  class NamespaceNotFoundError < FatalDeploymentError
    def initialize(name, context)
      super("Namespace `#{name}` not found in context `#{context}`")
    end
  end
  module Errors
    extend self
    def server_version_warning(server_version)
      "Minimum cluster version requirement of #{MIN_KUBE_VERSION} not met. "\
      "Using #{server_version} could result in unexpected behavior as it is no longer tested against"
    end
  end
end
