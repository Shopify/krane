# frozen_string_literal: true
require 'tempfile'

require 'kubernetes-deploy/kubeclient_builder'
require 'kubernetes-deploy/kubectl'

module KubernetesDeploy
  class RunnerTask
    include KubeclientBuilder

    class TaskTemplateMissingError < TaskConfigurationError; end

    attr_reader :pod_name

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
      start = Time.now.utc
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
        record_status_once(pod)
      end
      StatsD.distribution('task_runner.duration', StatsD.duration(start), tags: statsd_tags('success'))
      @logger.print_summary(:success)
    rescue DeploymentTimeoutError
      StatsD.distribution('task_runner.duration', StatsD.duration(start), tags: statsd_tags('timeout'))
      @logger.print_summary(:timed_out)
      raise
    rescue FatalDeploymentError
      StatsD.distribution('task_runner.duration', StatsD.duration(start), tags: statsd_tags('failure'))
      @logger.print_summary(:failure)
      raise
    end

    private

    def create_pod(pod)
      @logger.info("Creating pod '#{pod.name}'")
      pod.deploy_started_at = Time.now.utc
      kubeclient.create_pod(pod.to_kubeclient_resource)
      @pod_name = pod.name
      @logger.info("Pod creation succeeded")
    rescue Kubeclient::HttpError => e
      msg = "Failed to create pod: #{e.class.name}: #{e.message}"
      @logger.summary.add_paragraph(msg)
      raise FatalDeploymentError, msg
    end

    def build_pod(template_name, entrypoint, args, env_vars, verify_result)
      task_template = get_template(template_name)
      @logger.info("Using template '#{template_name}'")
      pod_template = build_pod_definition(task_template)
      set_container_overrides!(pod_template, entrypoint, args, env_vars)
      ensure_valid_restart_policy!(pod_template, verify_result)
      Pod.new(namespace: @namespace, context: @context, logger: @logger, stream_logs: true,
                    definition: pod_template.to_hash.deep_stringify_keys, statsd_tags: [])
    end

    def validate_pod(pod)
      pod.validate_definition(kubectl)
    end

    def watch_pod(pod)
      rw = ResourceWatcher.new(resources: [pod], logger: @logger, timeout: @max_watch_seconds,
        operation_name: "run", namespace: @namespace, context: @context)
      rw.run(delay_sync: 1, reminder_interval: 30.seconds)
      raise DeploymentTimeoutError if pod.deploy_timed_out?
      raise FatalDeploymentError if pod.deploy_failed?
    end

    def record_status_once(pod)
      cache = ResourceCache.new(@namespace, @context, @logger)
      pod.sync(cache)
      warning = <<~STRING
        #{ColorizedString.new('Result verification is disabled for this task.').yellow}
        The following status was observed immediately after pod creation:
        #{pod.pretty_status}
      STRING
      @logger.summary.add_paragraph(warning)
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
        @logger.info("Using namespace '#{@namespace}' in context '#{@context}'")
      rescue Kubeclient::HttpError => e
        msg = e.error_code == 404 ? "Namespace was not found" : "Could not connect to kubernetes cluster"
        errors << msg
      end

      unless errors.empty?
        @logger.summary.add_action("Configuration invalid")
        @logger.summary.add_paragraph(errors.map { |err| "- #{err}" }.join("\n"))
        raise TaskConfigurationError, "Configuration invalid: #{errors.join(', ')}"
      end

      if kubectl.server_version < Gem::Version.new(MIN_KUBE_VERSION)
        @logger.warn(KubernetesDeploy::Errors.server_version_warning(kubectl.server_version))
      end
    end

    def get_template(template_name)
      pod_template = kubeclient.get_pod_template(template_name, @namespace)

      pod_template.template
    rescue Kubeclient::HttpError => error
      if error.error_code == 404
        msg = "Pod template `#{template_name}` not found in namespace `#{@namespace}`, context `#{@context}`"
        @logger.summary.add_paragraph(msg)
        raise TaskTemplateMissingError, msg
      else
        raise FatalKubeAPIError, "Error retrieving pod template: #{error.class.name}: #{error.message}"
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
      container = pod_definition.spec.containers.find { |cont| cont.name == 'task-runner' }
      if container.nil?
        message = "Pod spec does not contain a template container called 'task-runner'"
        @logger.summary.add_paragraph(message)
        raise TaskConfigurationError, message
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
        @logger.warn("Changed Pod RestartPolicy from '#{restart_policy}' to 'Never'. Disable "\
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

    def statsd_tags(status)
      %W(namespace:#{@namespace} context:#{@context} status:#{status})
    end
  end
end
