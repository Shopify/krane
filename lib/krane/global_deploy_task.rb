# frozen_string_literal: true
require 'kubernetes-deploy/deploy_task'

module Krane
  class GlobalDeployTask < KubernetesDeploy::DeployTask
    def initialize(**args)
      super(args.merge(allow_globals: true, namespace: 'default', protected_namespaces: ''))
    end

    private

    def validate_globals(resources)
      return unless (namespaced = resources.reject(&:global?).presence)
      namespaced_names = namespaced.map do |resource|
        "#{resource.name} (#{resource.type}) in #{File.basename(resource.file_path)}"
      end
      namespaced_names = KubernetesDeploy::FormattedLogger.indent_four(namespaced_names.join("\n"))

      @logger.summary.add_paragraph(ColorizedString.new("Namespaced resources:\n#{namespaced_names}").yellow)
      raise KubernetesDeploy::FatalDeploymentError, "Deploying namespaced resource is not allowed from this command."
    end
  end
end
