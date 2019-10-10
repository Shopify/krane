# frozen_string_literal: true
require 'kubernetes-deploy/deploy_task'
require 'kubernetes-deploy/global_deploy_task_config_validator'

module Krane
  class GlobalDeployTask < KubernetesDeploy::DeployTask
    def initialize(**args)
      super(args.merge(allow_globals: true))
    end

    def run!(**args)
      super(args.merge(task_config_validator: KubernetesDeploy::GlobalDeployTaskConfigValidator))
    end
  end
end
