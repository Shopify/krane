# frozen_string_literal: true

require 'kubernetes-deploy/deploy_task'

module Krane
  class DeployTask < KubernetesDeploy::DeployTask
    def initialize(**args)
      super(args.merge(allow_globals: false))
    end
  end
end
