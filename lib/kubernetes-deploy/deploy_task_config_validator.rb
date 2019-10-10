# frozen_string_literal: true
module KubernetesDeploy
  class DeployTaskConfigValidator < TaskConfigValidator
    def initialize(protected_namespaces, allow_protected_ns, prune, *arguments)
      super(*arguments)
      @protected_namespaces = protected_namespaces
      @allow_protected_ns = allow_protected_ns
      @prune = prune
      @validations += %i(validate_protected_namespaces)
    end

    def validate_resources(resources, allow_globals)
      return unless (global = resources.select(&:global?).presence)
      global_names = global.map do |resource|
        "#{resource.name} (#{resource.type}) in #{File.basename(resource.file_path)}"
      end
      global_names = FormattedLogger.indent_four(global_names.join("\n"))

      if allow_globals
        msg = "The ability for this task to deploy global resources will be removed in the next version,"\
              " which will affect the following resources:"
        msg += "\n#{global_names}"
        logger.summary.add_paragraph(ColorizedString.new(msg).yellow)
      else
        logger.summary.add_paragraph(ColorizedString.new("Global resources:\n#{global_names}").yellow)
        raise FatalDeploymentError, "This command is namespaced and cannot be used to deploy global resources."
      end
    end

    private

    def validate_protected_namespaces
      if @protected_namespaces.include?(namespace)
        if @allow_protected_ns && @prune
          @errors << "Refusing to deploy to protected namespace '#{namespace}' with pruning enabled"
        elsif @allow_protected_ns
          logger.warn("You're deploying to protected namespace #{namespace}, which cannot be pruned.")
          logger.warn("Existing resources can only be removed manually with kubectl. " \
            "Removing templates from the set deployed will have no effect.")
          logger.warn("***Please do not deploy to #{namespace} unless you really know what you are doing.***")
        else
          @errors << "Refusing to deploy to protected namespace '#{namespace}'"
        end
      end
    end
  end
end
