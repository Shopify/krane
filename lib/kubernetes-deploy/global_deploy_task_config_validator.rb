# frozen_string_literal: true
module KubernetesDeploy
  class GlobalDeployTaskConfigValidator < TaskConfigValidator
    def initialize(protected_namespaces, allow_protected_ns, prune, *arguments)
      super(*arguments, skip: [:validate_namespace_exists])
      @protected_namespaces = protected_namespaces
      @allow_protected_ns = allow_protected_ns
      @prune = prune
    end
  end
end
