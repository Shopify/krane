# frozen_string_literal: true
module KubernetesDeploy
  class DeployTaskConfigValidator < TaskConfigValidator
    def initialize(protected_namespaces, allow_protected_ns, prune, *arguments)
      super(*arguments)
      @protected_namespaces = protected_namespaces
      @allow_protected_ns = allow_protected_ns
      @prune = prune
      @validations += %i(validate_protected_namespaces confirm_ejson_keys_not_prunable)
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

    def confirm_ejson_keys_not_prunable
      return unless ejson_keys_secret.dig("metadata", "annotations", KubernetesResource::LAST_APPLIED_ANNOTATION)
      return unless @prune

      @errors << "Deploy cannot proceed because protected resource " \
        "Secret/#{EjsonSecretProvisioner::EJSON_KEYS_SECRET} would be pruned. " \
        "Found #{KubernetesResource::LAST_APPLIED_ANNOTATION} annotation on " \
        "#{EjsonSecretProvisioner::EJSON_KEYS_SECRET} secret. " \
        "kubernetes-deploy will not continue since it is extremely unlikely that this secret should be pruned."
    rescue Kubectl::ResourceNotFoundError => e
      logger.debug("Secret/#{EjsonSecretProvisioner::EJSON_KEYS_SECRET} does not exist: #{e}")
    end

    def ejson_keys_secret
      @task_config.ejson_keys_secret ||= begin
        out, err, st = @kubectl.run("get", "secret", EjsonSecretProvisioner::EJSON_KEYS_SECRET, output: "json",
          raise_if_not_found: true, attempts: 3, output_is_sensitive: true, log_failure: true)
        unless st.success?
          raise EjsonSecretError, "Error retrieving Secret/#{EjsonSecretProvisioner::EJSON_KEYS_SECRET}: #{err}"
        end
        JSON.parse(out)
      end
    end

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
