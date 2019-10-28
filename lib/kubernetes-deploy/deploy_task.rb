# frozen_string_literal: true
require 'krane/deprecated_deploy_task'
require 'kubernetes-deploy/rescue_krane_exceptions'

module KubernetesDeploy
  class DeployTask < ::Krane::DeprecatedDeployTask
    include RescueKraneExceptions

    def run(*args)
      super(*args)
    rescue KubernetesDeploy::FatalDeploymentError
      false
    end
  end
end
