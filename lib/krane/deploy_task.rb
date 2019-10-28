# frozen_string_literal: true

require 'krane/deprecated_deploy_task'

module Krane
  class DeployTask < Krane::DeprecatedDeployTask
    def initialize(**args)
      raise "Use Krane::DeployGlobalTask to deploy global resources" if args[:allow_globals]
      super(args.merge(allow_globals: false))
    end
  end
end
