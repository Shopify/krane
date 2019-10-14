# frozen_string_literal: true
module KubernetesDeploy
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
end
