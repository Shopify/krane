# frozen_string_literal: true

module KubernetesDeploy
  class RestartTaskConfig < TaskConfig
    def deployments
      @deployments ||= fetch_deployments
    end

    def deployment_names
      deployments.map { |d| d.metadata.name }
    end

    def use_annotation?
      @extra_config[:use_annotation]
    end

    private

    def validate_task_specifics
      validate_restart_targets
    end

    def validate_restart_targets
      if use_annotation? && deployments.empty?
        @errors << "No deployments with the `#{RestartTask::ANNOTATION}` annotation found in namespace #{@namespace}"
      elsif deployments_requested.empty?
        @errors << "Configured to restart deployments by name, but list of names was blank"
      elsif missing = (deployments_requested - deployment_names).presence
        @errors << "No deployments with names #{missing.join(', ')} found in namespace #{@namespace}"
      end
    end

    def deployments_requested
      @extra_config.fetch(:deployments_requested, []).uniq
    end

    def fetch_deployments
      if use_annotation?
        all_deployments = v1beta1_kubeclient.get_deployments(namespace: @namespace)
        all_deployments.select { |d| d.metadata.annotations[ANNOTATION].present? }
      else
        named_deployments.map { |n| fetch_deployment(n) }.compact
      end
    end

    def fetch_deployment(name)
      with_kube_exception_retries { v1beta1_kubeclient.get_deployment(name, @namespace) }
    rescue Kubeclient::ResourceNotFoundError
      nil
    rescue Kubeclient::HttpError => error
      raise FatalKubeAPIError, "Error retrieving deployment: #{error}"
    end

    def v1beta1_kubeclient
      @v1beta1_kubeclient ||= build_v1beta1_kubeclient(@context)
    end
  end
end
