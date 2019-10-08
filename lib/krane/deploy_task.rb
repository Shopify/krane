# frozen_string_literal: true

require 'kubernetes-deploy/deploy_task'

module Krane
  class DeployTask < KubernetesDeploy::DeployTask
    def initialize(**args)
      raise "Use Krane::DeployGlobalTask to deploy global resources" if args[:allow_globals]
      super(args.merge(allow_globals: false))
    end
  end
end
