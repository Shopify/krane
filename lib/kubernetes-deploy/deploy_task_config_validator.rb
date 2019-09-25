# frozen_string_literal: true
module KubernetesDeploy
  class DeployTaskConfigValidator < TaskConfigValidator
    PROTECTED_NAMESPACES = %w(
      default
      kube-system
      kube-public
    )

    def initialize(allow_protected_ns, prune, *arguments)
      super(*arguments)
      @allow_protected_ns = allow_protected_ns
      @prune = prune
      @validations += %i(validate_protected_namespaces)
    end

    private

    def validate_protected_namespaces
      if PROTECTED_NAMESPACES.include?(namespace)
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
