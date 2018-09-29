# frozen_string_literal: true
require 'tempfile'

require 'kubernetes-deploy/kubeclient_builder'
require 'kubernetes-deploy/kubectl'

module KubernetesDeploy
  class RunnerTask
    include KubeclientBuilder

    RESULT_VERIFICATION_WARNING = <<~MSG
      Result verification is disabled for this task.
      This means the desired pod was successfully created, but the runner did not make sure it actually succeeded.
    MSG
    REQUIRED_CONTAINER_NAME = 'task-runner'

    class TaskTemplateMissingError < FatalDeploymentError
      def initialize(task_template, namespace, context)
        super("Pod template `#{task_template}` cannot be found in namespace `#{namespace}`, context `#{context}`")
      end
    end

    def initialize(namespace:, context:, logger:, max_watch_seconds: nil)
      @logger = logger
      @namespace = namespace
      @context = context
      @max_watch_seconds = max_watch_seconds
    end

    def run(*args)
      run!(*args)
      true
    rescue DeploymentTimeoutError, FatalDeploymentError
      false
    end

    def run!(task_template:, entrypoint:, args:, env_vars: [], verify_result: true)
      @logger.reset

      @logger.phase_heading("Initializing task")
      validate_configuration(task_template, args)
      pod = build_pod(task_template, entrypoint, args, env_vars, verify_result)
      validate_pod(pod)

      @logger.phase_heading("Running pod")
      create_pod(pod)

      if verify_result
        @logger.phase_heading("Streaming logs")
        watch_pod(pod)
      else
        @logger.summary.add_paragraph(ColorizedString.new(RESULT_VERIFICATION_WARNING).yellow)
      end
      @logger.print_summary(:success)
    rescue DeploymentTimeoutError => e
      @logger.summary.add_action(e.message) if e.message != e.class.to_s
      @logger.print_summary(:timed_out)
      raise
    rescue FatalDeploymentError => e
      @logger.summary.add_action(e.message) if e.message != e.class.to_s
      @logger.print_summary(:failure)
      raise
    end

    private

    def create_pod(pod)
      pod.deploy_started_at = Time.now.utc
      kubeclient.create_pod(Kubeclient::Resource.new(pod.definition))
      @logger.info("Pod '#{pod.name}' created")
    end

    def build_pod(template_name, entrypoint, args, env_vars, verify_result)
      @logger.info("Using template '#{template_name}' from namespace '#{@namespace}'")
      task_template = get_template(template_name)
      pod_template = build_pod_definition(task_template)
      set_container_overrides!(pod_template, entrypoint, args, env_vars)
      ensure_valid_restart_policy!(pod_template, verify_result)
      Pod.new(namespace: @namespace, context: @context, logger: @logger,
        definition: pod_template.to_hash.deep_stringify_keys, statsd_tags: [])
    end

    def validate_pod(pod)
      pod.validate_definition(kubectl)
    end

    def watch_pod(pod)
      mediator = SyncMediator.new(namespace: @namespace, context: @context, logger: @logger)
      streamer = ContainerLogStreamer.new(pod, REQUIRED_CONTAINER_NAME, @context, @logger, mediator)
      streamer.run(timeout: @max_watch_seconds)
    end

    def validate_configuration(task_template, args)
      @logger.info("Validating configuration")
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
        kubeclient.get_namespace(@namespace) if @namespace.present?
      rescue KubeException => e
        msg = e.error_code == 404 ? "Namespace was not found" : "Could not connect to kubernetes cluster"
        errors << msg
      end

      raise FatalTaskRunError, "Configuration invalid: #{errors.join(', ')}" unless errors.empty?

      if kubectl.server_version < Gem::Version.new(MIN_KUBE_VERSION)
        @logger.warn(KubernetesDeploy::Errors.server_version_warning(kubectl.server_version))
      end
    end

    def get_template(template_name)
      pod_template = kubeclient.get_pod_template(template_name, @namespace)

      pod_template.template
    rescue KubeException => error
      if error.error_code == 404
        raise TaskTemplateMissingError.new(template_name, @namespace, @context)
      else
        raise FatalDeploymentError, "Error communicating with the API server"
      end
    end

    def build_pod_definition(base_template)
      pod_definition = base_template.dup
      pod_definition.kind = 'Pod'
      pod_definition.apiVersion = 'v1'
      pod_definition.metadata.namespace = @namespace

      unique_name = pod_definition.metadata.name + "-" + SecureRandom.hex(8)
      @logger.warn("Name is too long, using '#{unique_name[0..62]}'") if unique_name.length > 63
      pod_definition.metadata.name = unique_name[0..62]

      pod_definition
    end

    def set_container_overrides!(pod_definition, entrypoint, args, env_vars)
      container = pod_definition.spec.containers.find { |cont| cont.name == REQUIRED_CONTAINER_NAME }
      if container.nil?
        raise FatalTaskRunError, "Pod spec does not contain a template container called '#{REQUIRED_CONTAINER_NAME}'"
      end

      container.command = entrypoint
      container.args = args

      env_args = env_vars.map do |env|
        key, value = env.split('=', 2)
        { name: key, value: value }
      end
      container.env ||= []
      container.env = container.env.map(&:to_h) + env_args
    end

    def ensure_valid_restart_policy!(template, verify)
      restart_policy = template.spec.restartPolicy
      if verify && restart_policy != "Never"
        @logger.warn("Changed Pod RestartPolicy from '#{restart_policy}' to 'Never'. Disable"\
          "result verification to use '#{restart_policy}'.")
        template.spec.restartPolicy = "Never"
      end
    end

    def kubectl
      @kubectl ||= Kubectl.new(namespace: @namespace, context: @context, logger: @logger, log_failure_by_default: true)
    end

    def kubeclient
      @kubeclient ||= build_v1_kubeclient(@context)
    end
  end
end
