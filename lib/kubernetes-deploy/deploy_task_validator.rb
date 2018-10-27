module KubernetesDeploy
  class DeployTaskValidator < TaskValidator

    private

    def validate_extra_config
      validate_template_dir(@required_args[:template_dir])
      validate_namespace_protection(@extra_config[:protected_ns_allowed], @extra_config[:pruning_enabled])
    end

    def validate_template_dir(template_dir)
      return unless template_dir.present?

      if !File.directory?(template_dir)
        @errors << "Template directory `#{template_dir}` doesn't exist"
      elsif Dir.entries(template_dir).none? { |file| file =~ /\.ya?ml(\.erb)?$/ }
        @errors << "`#{template_dir}` doesn't contain valid templates (postfix .yml or .yml.erb)"
      end
    end

    def validate_namespace_protection(protected_allowed, pruning_enabled)
      return unless KubernetesDeploy::DeployTask::PROTECTED_NAMESPACES.include?(@namespace)

      if protected_allowed && pruning_enabled
        errors << "Refusing to deploy to protected namespace '#{@namespace}' with pruning enabled"
      elsif protected_allowed
        warning = <<~STRING
          You're deploying to protected namespace #{@namespace}, which cannot be pruned.
          Existing resources can only be removed manually. Removing templates from the set deployed will have no efdfect.
          ***Please do not deploy to #{@namespace} unless you really know what you are doing.**
        STRING
        @warnings << warning
      else
        @errors << "Refusing to deploy to protected namespace '#{@namespace}'"
      end
    end

  end
end
