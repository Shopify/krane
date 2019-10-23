# frozen_string_literal: true
require 'kubernetes-deploy/errors'

module RescueKraneExceptions
  def run!(*args)
    super(*args)
  rescue Krane::DeploymentTimeoutError => e
    raise KubernetesDeploy::DeploymentTimeoutError, e.message
  rescue Krane::FatalDeploymentError => e
    raise KubernetesDeploy::FatalDeploymentError, e.message
  rescue Krane::FatalKubeAPIError => e
    raise KubernetesDeploy::FatalKubeAPIError, e.message
  rescue Krane::KubectlError => e
    raise KubernetesDeploy::KubectlError, e.message
  end
end
