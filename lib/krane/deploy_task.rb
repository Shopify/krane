# frozen_string_literal: true

require 'krane/deprecated_deploy_task'

module Krane
  class DeployTask < Krane::DeprecatedDeployTask
    def initialize(**args)
      raise "Use Krane::DeployGlobalTask to deploy global resources" if args[:allow_globals]
      super(args.merge(allow_globals: false))
    end

    def prune_whitelist
      black_list = %w(batch/v1beta1/Job)
      cluster_resource_discoverer.prunable_resources.select do |gvk|
        @task_config.namespaced_kinds.any? { |g| gvk.include?(g) } && black_list.none? { |b| gvk.include?(b) }
      end
    end
  end
end
