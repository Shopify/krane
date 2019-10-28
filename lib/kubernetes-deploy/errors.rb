# frozen_string_literal: true

module KubernetesDeploy
  class FatalDeploymentError < StandardError; end
  class FatalKubeAPIError < FatalDeploymentError; end
  class KubectlError < StandardError; end
  class DeploymentTimeoutError < FatalDeploymentError; end
end
