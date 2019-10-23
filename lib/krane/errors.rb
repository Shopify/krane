# frozen_string_literal: true
module Krane
  class FatalDeploymentError < StandardError; end
  class FatalKubeAPIError < FatalDeploymentError; end
  class KubectlError < StandardError; end
  class TaskConfigurationError < FatalDeploymentError; end

  class InvalidTemplateError < FatalDeploymentError
    attr_reader :content
    attr_accessor :filename
    def initialize(err, filename: nil, content: nil)
      @filename = filename
      @content = content
      super(err)
    end
  end

  class NamespaceNotFoundError < FatalDeploymentError
    def initialize(name, context)
      super("Namespace `#{name}` not found in context `#{context}`")
    end
  end

  class DeploymentTimeoutError < FatalDeploymentError; end

  class EjsonPrunableError < FatalDeploymentError
    def initialize
      super("Found #{KubernetesResource::LAST_APPLIED_ANNOTATION} annotation on " \
          "#{EjsonSecretProvisioner::EJSON_KEYS_SECRET} secret. " \
          "krane will not continue since it is extremely unlikely that this secret should be pruned.")
    end
  end
end
