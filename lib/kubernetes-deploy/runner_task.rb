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
      if kubectl.server_version < Gem::Version.new(MIN_KUBE_VERSION)
        @logger.warn(KubernetesDeploy::Errors.server_version_warning(kubectl.server_version))
      end
      raw_template = get_template(task_template)

      rendered_template = build_pod_template(raw_template, entrypoint, args, env_vars)
      validate_restart_policy(rendered_template, verify_result)
      pod = Pod.new(namespace: @namespace, context: @context, logger: @logger, log_on_success: false,
                    definition: rendered_template.to_hash.deep_stringify_keys, statsd_tags: [])
      pod.validate_definition(kubectl)
      @logger.info("Configuration valid")
      @logger.phase_heading("Creating pod")
      @logger.info("Starting task runner pod: '#{rendered_template.metadata.name}'")

      pod_creation_time = Time.now.utc
      pod.deploy_started_at = pod_creation_time
      @kubeclient.create_pod(rendered_template)

      if verify_result
        sync_mediator = SyncMediator.new(namespace: @namespace, context: @context, logger: @logger)
        watch_and_report(pod, pod_creation_time, sync_mediator)
      else
        warning = <<~MSG
          Result verification is disabled for this task.
          This means the desired pod was successfully created, but the runner did not make sure it actually succeeded.
        MSG
        @logger.summary.add_paragraph(ColorizedString.new(warning).yellow)
      end
    end

    private

    def watch_and_report(pod, deploy_started_at, sync_mediator)
      sync_interval = 5.seconds
      last_loop_time = last_log_time = deploy_started_at
      @logger.info("Logs from #{pod.id}:")

      loop do
        pod.sync(sync_mediator)
        logs = pod.fetch_logs(kubectl, since: last_log_time.to_datetime.rfc3339)
        last_log_time = Time.now.utc

        logs.each do |_, log|
          if log.present?
            @logger.info("\t" + log.join("\n\t"))
          else
            @logger.info("\t...")
          end
        end

        if (sleep_duration = sync_interval - (Time.now.utc - last_loop_time)) > 0
          sleep(sleep_duration)
        end
        last_loop_time = Time.now.utc

        return if deploy_ended?(pod, deploy_started_at)
      end
    end

    def deploy_ended?(pod, deploy_started_at)
      if pod.deploy_succeeded?
        @logger.summary.add_action("Successfully ran pod")
        @logger.print_summary(:success)
        return true
      elsif pod.deploy_failed?
        @logger.summary.add_action("Failed to deploy pod")
        @logger.summary.add_paragraph(pod.debug_message)
        @logger.print_summary(:failure)
        raise FatalDeploymentError
      elsif pod.deploy_timed_out?
        @logger.summary.add_action("Timed out waiting for pod")
        @logger.summary.add_paragraph(pod.debug_message)
        @logger.print_summary(:timed_out)
        raise DeploymentTimeoutError
      elsif @max_watch_seconds.present? && Time.now.utc - deploy_started_at > @max_watch_seconds
        @logger.summary.add_action("Timed out waiting for pod")
        @logger.summary.add_paragraph(pod.debug_message(:gave_up, timeout: @max_watch_seconds))
        @logger.print_summary(:timed_out)
        raise DeploymentTimeoutError
      end

      false
    end

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
        raise FatalDeploymentError, "Error communication with the API server"
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
