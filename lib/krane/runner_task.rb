# frozen_string_literal: true
require 'tempfile'

require 'krane/common'
require 'krane/kubeclient_builder'
require 'krane/kubectl'
require 'krane/resource_cache'
require 'krane/resource_watcher'
require 'krane/kubernetes_resource'
require 'krane/kubernetes_resource/pod'
require 'krane/runner_task_config_validator'
require 'krane/container_overrides'

module Krane
  # Run a pod that exits upon completing a task
  class RunnerTask
    class TaskTemplateMissingError < TaskConfigurationError; end

    attr_reader :pod_name, :task_config

    delegate :kubeclient_builder, to: :task_config

    # Initializes the runner task
    #
    # @param namespace [String] Kubernetes namespace (*required*)
    # @param context [String] Kubernetes context / cluster (*required*)
    # @param logger [Object] Logger object (defaults to an instance of Krane::FormattedLogger)
    # @param global_timeout [Integer] Timeout in seconds
    def initialize(namespace:, context:, logger: nil, global_timeout: nil, kubeconfig: nil)
      @logger = logger || Krane::FormattedLogger.build(namespace, context)
      @task_config = Krane::TaskConfig.new(context, namespace, @logger, kubeconfig)
      @namespace = namespace
      @context = context
      @global_timeout = global_timeout
    end

    # Runs the task, returning a boolean representing success or failure
    #
    # @return [Boolean]
    def run(**args)
      run!(**args)
      true
    rescue DeploymentTimeoutError, FatalDeploymentError
      false
    end

    # Runs the task, raising exceptions in case of issues
    #
    # @param template [String] The filename of the template you'll be rendering (*required*)
    # @param command [Array<String>] Override the default command in the container image
    # @param arguments [Array<String>] Override the default arguments for the command
    # @param env_vars [Array<String>] List of env vars
    # @param verify_result [Boolean] Wait for completion and verify pod success
    #
    # @return [nil]
    def run!(template:, command:, arguments:, env_vars: [], image_tag: nil, verify_result: true)
      start = Time.now.utc
      @logger.reset

      @logger.phase_heading("Initializing task")

      @logger.info("Validating configuration")
      verify_config!(template)
      @logger.info("Using namespace '#{@namespace}' in context '#{@context}'")
      container_overrides = ContainerOverrides.new(
        command: command,
        arguments: arguments,
        env_vars: env_vars,
        image_tag: image_tag
      )
      pod = build_pod(template, container_overrides, verify_result)
      validate_pod(pod)

      @logger.phase_heading("Running pod")
      create_pod(pod)

      if verify_result
        @logger.phase_heading("Streaming logs")
        watch_pod(pod)
      else
        record_status_once(pod)
      end
      StatsD.client.distribution('task_runner.duration', StatsD.duration(start), tags: statsd_tags('success'))
      @logger.print_summary(:success)
    rescue DeploymentTimeoutError
      StatsD.client.distribution('task_runner.duration', StatsD.duration(start), tags: statsd_tags('timeout'))
      @logger.print_summary(:timed_out)
      raise
    rescue FatalDeploymentError
      StatsD.client.distribution('task_runner.duration', StatsD.duration(start), tags: statsd_tags('failure'))
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

    def build_pod(template_name, container_overrides, verify_result)
      task_template = get_template(template_name)
      @logger.info("Using template '#{template_name}'")
      pod_template = build_pod_definition(task_template)
      container = extract_task_runner_container(pod_template)
      container_overrides.apply!(container)
      ensure_valid_restart_policy!(pod_template, verify_result)
      Pod.new(namespace: @namespace, context: @context, logger: @logger, stream_logs: true,
                    definition: pod_template.to_hash.deep_stringify_keys, statsd_tags: [])
    end

    def validate_pod(pod)
      pod.validate_definition(kubectl: kubectl)
    end

    def watch_pod(pod)
      rw = ResourceWatcher.new(resources: [pod], timeout: @global_timeout,
        operation_name: "run", task_config: @task_config)
      rw.run(delay_sync: 1, reminder_interval: 30.seconds)
      raise DeploymentTimeoutError if pod.deploy_timed_out?
      raise FatalDeploymentError if pod.deploy_failed?
    end

    def record_status_once(pod)
      cache = ResourceCache.new(@task_config)
      pod.sync(cache)
      warning = <<~STRING
        #{ColorizedString.new('Result verification is disabled for this task.').yellow}
        The following status was observed immediately after pod creation:
        #{pod.pretty_status}
      STRING
      @logger.summary.add_paragraph(warning)
    end

    def verify_config!(task_template)
      task_config_validator = RunnerTaskConfigValidator.new(task_template, @task_config, kubectl,
        kubeclient_builder)
      unless task_config_validator.valid?
        @logger.summary.add_action("Configuration invalid")
        @logger.summary.add_paragraph([task_config_validator.errors].map { |err| "- #{err}" }.join("\n"))
        raise Krane::TaskConfigurationError
      end
    end

    def get_template(template_name)
      pod_template = kubeclient.get_pod_template(template_name, @namespace)
      pod_template.template
    rescue Kubeclient::ResourceNotFoundError
      msg = "Pod template `#{template_name}` not found in namespace `#{@namespace}`, context `#{@context}`"
      @logger.summary.add_paragraph(msg)
      raise TaskTemplateMissingError, msg
    rescue Kubeclient::HttpError => error
      raise FatalKubeAPIError, "Error retrieving pod template: #{error.class.name}: #{error.message}"
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

    def extract_task_runner_container(pod_definition)
      container = pod_definition.spec.containers.find { |cont| cont.name == 'task-runner' }
      if container.nil?
        message = "Pod spec does not contain a template container called 'task-runner'"
        @logger.summary.add_paragraph(message)
        raise TaskConfigurationError, message
      end

      container
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
      @kubectl ||= Kubectl.new(task_config: @task_config, log_failure_by_default: true)
    end

    def kubeclient
      @kubeclient ||= kubeclient_builder.build_v1_kubeclient(@context)
    end

    def statsd_tags(status)
      %W(namespace:#{@namespace} context:#{@context} status:#{status})
    end
  end
end
