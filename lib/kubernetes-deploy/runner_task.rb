# frozen_string_literal: true
require 'tempfile'

require 'kubernetes-deploy/kubeclient_builder'
require 'kubernetes-deploy/kubectl'
require 'kubernetes-deploy/resource_reporting_watcher'

module KubernetesDeploy
  class RunnerTask
    include KubeclientBuilder

    class FatalTaskRunError < FatalDeploymentError; end
    class TaskTemplateMissingError < FatalDeploymentError
      def initialize(task_template, namespace, context)
        super("Pod template `#{task_template}` cannot be found in namespace: `#{namespace}`, context: `#{context}`")
      end
    end

    def initialize(namespace:, context:, logger:, max_watch_seconds: nil)
      @logger = logger
      @namespace = namespace
      @kubeclient = build_v1_kubeclient(context)
      @context = context
      @max_watch_seconds = max_watch_seconds
    end

    def run(*args)
      run!(*args)
      true
    rescue DeploymentTimeoutError
      false
    rescue FatalDeploymentError => error
      if error.message != error.class.to_s
        @logger.summary.add_action(error.message)
        @logger.print_summary(:failure)
      end
      false
    end

    def run!(task_template:, entrypoint:, args:, env_vars: [], verify_result: true)
      @logger.reset
      @logger.phase_heading("Initializing deploy")
      validate_configuration(task_template, args)

      raw_template = get_template(task_template)
      rendered_template = build_pod_template(raw_template, entrypoint, args, env_vars)
      validate_restart_policy(rendered_template, verify_result)

      pod = Pod.new(namespace: @namespace, context: @context, logger: @logger, log_on_success: false,
                    definition: rendered_template.to_hash.deep_stringify_keys, statsd_tags: [])
      pod.validate_definition(kubectl)
      @logger.info("Configuration valid")

      @logger.phase_heading("Creating pod")

      @logger.info("Starting task runner pod: '#{rendered_template.metadata.name}'")
      pod.deploy_started_at = Time.now.utc
      @kubeclient.create_pod(rendered_template)

      if verify_result
        ResourceReportingWatcher.new(resource: pod, logger: @logger, timeout: @max_watch_seconds).run
      else
        warning = <<~MSG
          Result verification is disabled for this task.
          This means the desired pod was successfully created, but the runner did not make sure it actually succeeded.
        MSG
        @logger.summary.add_paragraph(ColorizedString.new(warning).yellow)
      end
    end

    private

    def validate_configuration(task_template, args)
      if kubectl.server_version < Gem::Version.new(MIN_KUBE_VERSION)
        @logger.warn(KubernetesDeploy::Errors.server_version_warning(kubectl.server_version))
      end

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
        raise FatalDeploymentError, "Error communicating with the API server"
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

    def validate_restart_policy(template, verify)
      if template.spec.restartPolicy != "Never" && verify
        raise FatalTaskRunError, "Configuration invalid: Pod RestartPolicy must be 'Never' unless '--skip-wait=true'"
      end
    end

    def kubectl
      @kubectl ||= Kubectl.new(namespace: @namespace, context: @context, logger: @logger, log_failure_by_default: true)
    end
  end
end
