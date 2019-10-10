# frozen_string_literal: true
module KubernetesDeploy
  class GlobalDeployTaskConfigValidator < TaskConfigValidator
    def initialize(protected_namespaces, allow_protected_ns, prune, *arguments)
      super(*arguments, skip: [:validate_namespace_exists])
      @protected_namespaces = protected_namespaces
      @allow_protected_ns = allow_protected_ns
      @prune = prune
    end

    def validate_resources(resources, _)
      return unless (namespaced = resources.reject(&:global?).presence)
      namespaced_names = namespaced.map do |resource|
        "#{resource.name} (#{resource.type}) in #{File.basename(resource.file_path)}"
      end
      namespaced_names = KubernetesDeploy::FormattedLogger.indent_four(namespaced_names.join("\n"))

      logger.summary.add_paragraph(ColorizedString.new("Namespaced resources:\n#{namespaced_names}").yellow)
      raise KubernetesDeploy::FatalDeploymentError, "Deploying namespaced resource is not allowed from this command."
    end
  end
end
