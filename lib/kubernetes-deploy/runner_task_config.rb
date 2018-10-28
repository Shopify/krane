# frozen_string_literal: true

module KubernetesDeploy
  class RunnerTaskConfig < TaskConfig
    MAX_NAME_LENGTH = 63

    def pod_definition
      @pod_definition ||= build_pod_definition
    end

    private

    def validate_task_specifics
      validate_pod_template
    end

    def validate_pod_template
      template = get_template
      if template.blank?
        @errors << "Pod template `#{task_template_name}` not found in namespace `#{@namespace}`, context `#{@context}`"
        return
      end

      if template.metadata.name.length > max_base_name_length
        @warnings << "Name #{template.metadata.name} is too long and will be truncated"
      end

      if override_restart_policy?(template)
        restart_policy = template.spec.restartPolicy
        @warnings << "Pod RestartPolicy will be changed from '#{restart_policy}' to 'Never'. Disable "\
          "result verification to use '#{restart_policy}'."
      end

      unless task_runner_container(pod_definition).present?
        @errors << "Pod spec has multiple containers, and none are named 'task-runner'"
      end
    end

    def task_template
      @task_template ||= with_kube_exception_retries do
        kubeclient.get_pod_template(task_template_name, @namespace).template
      end
    rescue Kubeclient::ResourceNotFoundError
      nil
    rescue Kubeclient::HttpError => error
      raise FatalKubeAPIError, "Error retrieving pod template: #{error}"
    end

    def task_template_name
      @required_args[:task_template]
    end

    def build_pod_definition
      pod_definition = task_template.dup
      pod_definition.kind = 'Pod'
      pod_definition.apiVersion = 'v1'
      pod_definition.metadata.namespace = @namespace
      pod_definition.metadata.name = unique_name(pod_definition.metadata.name)

      apply_container_overrides!(pod_definition)
      ensure_valid_restart_policy!(pod_definition)
      pod_definition
    end

    def unique_name(original_name)
      if original_name.length > max_base_name_length
        original_name.slice(0, max_base_name_length) + unique_suffix
      else
        original_name + unique_suffix
      end
    end

    def max_base_name_length
      MAX_NAME_LENGTH - unique_suffix.length
    end

    def unique_suffix
      "-#{SecureRandom.hex(8)}"
    end

    def apply_container_overrides!(pod_definition)
      container = task_runner_container(pod_definition)
      return if container.nil?

      container.command = @extra_config[:entrypoint] if @extra_config[:entrypoint]
      container.args = @extra_config[:args] if @extra_config[:args]

      env_args = @extra_config.fetch(:env_vars, []).map do |env|
        key, value = env.split('=', 2)
        { name: key, value: value }
      end
      container.env ||= []
      container.env = container.env.map(&:to_h) + env_args
    end

    def task_runner_container(pod_definition)
      return pod_definition.spec.containers.first if pod_definition.spec.containers.one?
      pod_definition.spec.containers.find { |cont| cont.name == 'task-runner' }
    end

    def ensure_valid_restart_policy!(template)
      if override_restart_policy?(template)
        template.spec.restartPolicy = "Never"
      end
    end

    def override_restart_policy?(template)
      @extra_config[:verify_result] ? template.spec.restartPolicy != "Never" : false
    end
  end
end
