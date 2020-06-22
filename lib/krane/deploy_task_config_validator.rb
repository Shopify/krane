# frozen_string_literal: true
module Krane
  class DeployTaskConfigValidator < TaskConfigValidator
    def initialize(protected_namespaces, prune, *arguments)
      super(*arguments)
      @protected_namespaces = protected_namespaces
      @allow_protected_ns = !protected_namespaces.empty?
      @prune = prune
      @validations += %i(validate_protected_namespaces)
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
