# frozen_string_literal: true
require 'krane/restart_task'
require 'kubernetes-deploy/rescue_krane_exceptions'

module KubernetesDeploy
  class RestartTask < ::Krane::RestartTask
    include RescueKraneExceptions

    def run(*args)
      super(*args)
    rescue KubernetesDeploy::FatalDeploymentError
      false
    end
  end
end
