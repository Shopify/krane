# frozen_string_literal: true
require 'tempfile'

require 'kubernetes-deploy/kubeclient_builder'
require 'kubernetes-deploy/kubectl'

module KubernetesDeploy
  class RunnerTask
    include KubeclientBuilder

    class FatalTaskRunError < FatalDeploymentError; end
    class TaskTemplateMissingError < FatalDeploymentError
      def initialize(task_template, namespace, context)
        super("Pod template `#{task_template}` cannot be found in namespace: `#{namespace}`, context: `#{context}`")
      end
    end

    def initialize(namespace:, context:, logger:)
      @logger = logger
      @namespace = namespace
      @kubeclient = build_v1_kubeclient(context)
      @context = context
    end

    def run(*args)
      run!(*args)
      true
    rescue FatalDeploymentError => error
      @logger.fatal "#{error.class}: #{error.message}"
      false
    end

    def run!(task_template:, entrypoint:, args:, env_vars: [])
      @logger.reset
      @logger.phase_heading("Validating configuration")
      validate_configuration(task_template, args)
      if kubectl.server_version < Gem::Version.new(MIN_KUBE_VERSION)
        @logger.warn(KubernetesDeploy::Errors.server_version_warning(kubectl.server_version))
      end
      @logger.phase_heading("Fetching task template")
      raw_template = get_template(task_template)

      @logger.phase_heading("Constructing final pod specification")
      rendered_template = build_pod_template(raw_template, entrypoint, args, env_vars)

      validate_pod_spec(rendered_template)

      @logger.phase_heading("Creating pod")
      @logger.info("Starting task runner pod: '#{rendered_template.metadata.name}'")
      @kubeclient.create_pod(rendered_template)
    end

    private

    def validate_configuration(task_template, args)
      errors = []

      if task_template.blank?
        errors << "Task template name can't be nil"
      end

      if @namespace.blank?
        errors << "Namespace can't be empty"
      end

      if args.blank?
        errors << "Args can't be nil"
      end

      begin
        @kubeclient.get_namespace(@namespace) if @namespace.present?
      rescue KubeException => e
        msg = e.error_code == 404 ? "Namespace was not found" : "Could not connect to kubernetes cluster"
        errors << msg
      end

      raise FatalTaskRunError, "Configuration invalid: #{errors.join(', ')}" unless errors.empty?
    end

    def get_template(template_name)
      @logger.info(
        "Fetching task runner pod template: '#{template_name}' in namespace: '#{@namespace}'"
      )

      pod_template = @kubeclient.get_pod_template(template_name, @namespace)

      pod_template.template
    rescue KubeException => error
      if error.error_code == 404
        raise TaskTemplateMissingError.new(template_name, @namespace, @context)
      else
        raise
      end
    end

    def build_pod_template(base_template, entrypoint, args, env_vars)
      @logger.info("Rendering template for task runner pod")

      rendered_template = base_template.dup
      rendered_template.kind = 'Pod'
      rendered_template.apiVersion = 'v1'

      container = rendered_template.spec.containers.find { |cont| cont.name == 'task-runner' }

      raise FatalTaskRunError, "Pod spec does not contain a template container called 'task-runner'" if container.nil?

      container.command = entrypoint
      container.args = args
      container.env ||= []

      env_args = env_vars.map do |env|
        key, value = env.split('=', 2)
        { name: key, value: value }
      end

      container.env = container.env.map(&:to_h) + env_args

      unique_name = rendered_template.metadata.name + "-" + SecureRandom.hex(8)

      @logger.warn("Name is too long, using '#{unique_name[0..62]}'") if unique_name.length > 63
      rendered_template.metadata.name = unique_name[0..62]
      rendered_template.metadata.namespace = @namespace

      rendered_template
    end

    def validate_pod_spec(pod)
      f = Tempfile.new(pod.metadata.name)
      f.write recursive_to_h(pod).to_json
      f.close

      _out, err, status = kubectl.run("apply", "--dry-run", "-f", f.path)

      unless status.success?
        raise FatalTaskRunError, "Invalid pod spec: #{err}"
      end
    end

    def kubectl
      @kubectl ||= Kubectl.new(namespace: @namespace, context: @context, logger: @logger, log_failure_by_default: true)
    end

    def recursive_to_h(struct)
      if struct.is_a?(Array)
        return struct.map { |v| v.is_a?(OpenStruct) || v.is_a?(Array) || v.is_a?(Hash) ? recursive_to_h(v) : v }
      end

      hash = {}

      struct.each_pair do |k, v|
        recursive_val = v.is_a?(OpenStruct) || v.is_a?(Array) || v.is_a?(Hash)
        hash[k] = recursive_val ? recursive_to_h(v) : v
      end
      hash
    end
  end
end
