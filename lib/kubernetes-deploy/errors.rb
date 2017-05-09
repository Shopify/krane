# frozen_string_literal: true
module KubernetesDeploy
  class FatalDeploymentError < StandardError; end
  class KubectlError < StandardError; end

  class NamespaceNotFoundError < FatalDeploymentError
    def initialize(name, context)
      super("Namespace `#{name}` not found in context `#{context}`. Aborting the task.")
    end
  end
end
