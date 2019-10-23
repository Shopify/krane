# frozen_string_literal: true
require 'krane/render_task'
require 'kubernetes-deploy/rescue_krane_exceptions'

module KubernetesDeploy
  class RenderTask < ::Krane::RenderTask
    include RescueKraneExceptions

    def run(*args)
      super(*args)
    rescue KubernetesDeploy::FatalDeploymentError
      false
    end
  end
end
