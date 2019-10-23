# frozen_string_literal: true
require 'krane/runner_task'
require 'kubernetes-deploy/rescue_krane_exceptions'

module KubernetesDeploy
  class RunnerTask < ::Krane::RunnerTask
    include RescueKraneExceptions

    def run(*args)
      super(*args)
    rescue KubernetesDeploy::DeploymentTimeoutError, KubernetesDeploy::FatalDeploymentError
      false
    end
  end
end
