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
      @logger.reset

      @logger.phase_heading("Initializing task")
      config = validate_configuration(task_template, entrypoint, args, env_vars, verify_result)
      pod = build_pod(config.pod_definition)
      validate_pod(pod)

      @logger.phase_heading("Running pod")
      create_pod(pod)

      if verify_result
        @logger.phase_heading("Streaming logs")
        watch_pod(pod)
      else
        record_status_once(pod)
      end
      @logger.print_summary(:success)
    rescue DeploymentTimeoutError
      @logger.print_summary(:timed_out)
      raise
    rescue FatalDeploymentError
      @logger.print_summary(:failure)
      raise
    end

    private

    def build_pod(pod_template)
      Pod.new(namespace: @namespace, context: @context, logger: @logger, stream_logs: true,
        definition: pod_template.to_hash.deep_stringify_keys, statsd_tags: [])
    end

    def create_pod(pod)
      @logger.info "Creating pod '#{pod.name}'"
      pod.deploy_started_at = Time.now.utc
      kubeclient.create_pod(pod.to_kubeclient_resource)
      @pod_name = pod.name
      @logger.info("Pod creation succeeded")
    rescue KubeException => e
      msg = "Failed to create pod: #{e.class.name}: #{e.message}"
      @logger.summary.add_paragraph(msg)
      raise FatalDeploymentError, msg
    end

    def watch_pod(pod)
      rw = ResourceWatcher.new(resources: [pod], logger: @logger, timeout: @max_watch_seconds,
        sync_mediator: sync_mediator, operation_name: "run")
      rw.run(delay_sync: 1, reminder_interval: 30.seconds)
      raise DeploymentTimeoutError if pod.deploy_timed_out?
      raise FatalDeploymentError if pod.deploy_failed?
    end

    def record_status_once(pod)
      pod.sync(sync_mediator)
      warning = <<~STRING
        #{ColorizedString.new('Result verification is disabled for this task.').yellow}
        The following status was observed immediately after pod creation:
        #{pod.pretty_status}
      STRING
      @logger.summary.add_paragraph(warning)
    end

    def validate_configuration(task_template, entrypoint, args, env_vars, verify_result)
      @logger.info("Validating configuration")

      required = { task_template: task_template, args: args }
      extra = { entrypoint: entrypoint, env_vars: env_vars, verify_result: verify_result }
      config = TaskConfig.new(@context, @namespace, required_args: required, extra_config: extra)

      unless config.valid?
        record_result(@logger)
        raise TaskConfigurationError, config.error_sentence
      end

      @logger.info "Using namespace '#{@namespace}' in context '#{@context}'"
      @logger.info("Using template '#{template_name}'")
      config
    end

    def validate_pod(pod)
      pod.validate_definition(kubectl)
    end

    def sync_mediator
      @sync_mediator ||= SyncMediator.new(namespace: @namespace, context: @context, logger: @logger)
    end

    def kubeclient
      @kubeclient ||= build_v1_kubeclient(@context)
    end

    def kubectl
      @kubectl ||= begin
        logger = KubernetesDeploy::FormattedLogger.build(@namespace, @context)
        Kubectl.new(namespace: @namespace, context: @context, logger: logger, log_failure_by_default: true)
      end
    end
  end
end
