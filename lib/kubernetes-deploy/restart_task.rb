# frozen_string_literal: true
require 'kubernetes-deploy/common'
require 'kubernetes-deploy/kubernetes_resource'
require 'kubernetes-deploy/kubernetes_resource/deployment'
require 'kubernetes-deploy/kubeclient_builder'
require 'kubernetes-deploy/resource_watcher'
require 'kubernetes-deploy/kubectl'

module KubernetesDeploy
  class RestartTask
    class FatalRestartError < FatalDeploymentError; end

    class RestartAPIError < FatalRestartError
      def initialize(deployment_name, response)
        super("Failed to restart #{deployment_name}. " \
            "API returned non-200 response code (#{response.code})\n" \
            "Response:\n#{response.body}")
      end
    end

    HTTP_OK_RANGE = 200..299
    ANNOTATION = "shipit.shopify.io/restart"

    def initialize(context:, namespace:, logger: nil, max_watch_seconds: nil)
      @logger = logger || KubernetesDeploy::FormattedLogger.build(namespace, context)
      @task_config = KubernetesDeploy::TaskConfig.new(context, namespace, @logger)
      @context = context
      @namespace = namespace
      @max_watch_seconds = max_watch_seconds
    end

    def run(*args)
      perform!(*args)
      true
    rescue FatalDeploymentError
      false
    end
    alias_method :perform, :run

    def run!(deployments_names = nil, selector: nil, verify_result: true)
      start = Time.now.utc
      @logger.reset

      @logger.phase_heading("Initializing restart")
      verify_config!
      deployments = identify_target_deployments(deployments_names, selector: selector)

      @logger.phase_heading("Triggering restart by touching ENV[RESTARTED_AT]")
      patch_kubeclient_deployments(deployments)

      if verify_result
        @logger.phase_heading("Waiting for rollout")
        resources = build_watchables(deployments, start)
        verify_restart(resources)
      else
        warning = "Result verification is disabled for this task"
        @logger.summary.add_paragraph(ColorizedString.new(warning).yellow)
      end
      StatsD.distribution('restart.duration', StatsD.duration(start), tags: tags('success', deployments))
      @logger.print_summary(:success)
    rescue DeploymentTimeoutError
      StatsD.distribution('restart.duration', StatsD.duration(start), tags: tags('timeout', deployments))
      @logger.print_summary(:timed_out)
      raise
    rescue FatalDeploymentError => error
      StatsD.distribution('restart.duration', StatsD.duration(start), tags: tags('failure', deployments))
      @logger.summary.add_action(error.message) if error.message != error.class.to_s
      @logger.print_summary(:failure)
      raise
    end
    alias_method :perform!, :run!

    private

    def tags(status, deployments)
      %W(namespace:#{@namespace} context:#{@context} status:#{status} deployments:#{deployments.to_a.length}})
    end

    def identify_target_deployments(deployment_names, selector: nil)
      if deployment_names.nil?
        deployments = if selector.nil?
          @logger.info("Configured to restart all deployments with the `#{ANNOTATION}` annotation")
          v1beta1_kubeclient.get_deployments(namespace: @namespace)
        else
          selector_string = selector.to_s
          @logger.info(
            "Configured to restart all deployments with the `#{ANNOTATION}` annotation and #{selector_string} selector"
          )
          v1beta1_kubeclient.get_deployments(namespace: @namespace, label_selector: selector_string)
        end
        deployments.select! { |d| d.metadata.annotations[ANNOTATION] }

        if deployments.none?
          raise FatalRestartError, "no deployments with the `#{ANNOTATION}` annotation found in namespace #{@namespace}"
        end
      elsif deployment_names.empty?
        raise FatalRestartError, "Configured to restart deployments by name, but list of names was blank"
      elsif !selector.nil?
        raise FatalRestartError, "Can't specify deployment names and selector at the same time"
      else
        deployment_names = deployment_names.uniq
        list = deployment_names.join(', ')
        @logger.info("Configured to restart deployments by name: #{list}")

        deployments = fetch_deployments(deployment_names)
        if deployments.none?
          raise FatalRestartError, "no deployments with names #{list} found in namespace #{@namespace}"
        end
      end
      deployments
    end

    def build_watchables(kubeclient_resources, started)
      kubeclient_resources.map do |d|
        definition = d.to_h.deep_stringify_keys
        r = Deployment.new(namespace: @namespace, context: @context, definition: definition, logger: @logger)
        r.deploy_started_at = started # we don't care what happened to the resource before the restart cmd ran
        r
      end
    end

    def patch_deployment_with_restart(record)
      v1beta1_kubeclient.patch_deployment(
        record.metadata.name,
        build_patch_payload(record),
        @namespace
      )
    end

    def patch_kubeclient_deployments(deployments)
      deployments.each do |record|
        begin
          patch_deployment_with_restart(record)
          @logger.info("Triggered `#{record.metadata.name}` restart")
        rescue Kubeclient::HttpError => e
          raise RestartAPIError.new(record.metadata.name, e.message)
        end
      end
    end

    def fetch_deployments(list)
      list.map do |name|
        record = nil
        begin
          record = v1beta1_kubeclient.get_deployment(name, @namespace)
        rescue Kubeclient::ResourceNotFoundError
          raise FatalRestartError, "Deployment `#{name}` not found in namespace `#{@namespace}`"
        end
        record
      end
    end

    def build_patch_payload(deployment)
      containers = deployment.spec.template.spec.containers
      {
        spec: {
          template: {
            spec: {
              containers: containers.map do |container|
                {
                  name: container.name,
                  env: [{ name: "RESTARTED_AT", value: Time.now.to_i.to_s }],
                }
              end,
            },
          },
        },
      }
    end

    def verify_restart(resources)
      ResourceWatcher.new(resources: resources, logger: @logger, operation_name: "restart",
        timeout: @max_watch_seconds, namespace: @namespace, context: @context).run
      failed_resources = resources.reject(&:deploy_succeeded?)
      success = failed_resources.empty?
      if !success && failed_resources.all?(&:deploy_timed_out?)
        raise DeploymentTimeoutError
      end
      raise FatalDeploymentError unless success
    end

    def verify_config!
      task_config_validator = TaskConfigValidator.new(@task_config, kubectl, kubeclient_builder)
      unless task_config_validator.valid?
        @logger.summary.add_action("Configuration invalid")
        @logger.summary.add_paragraph(task_config_validator.errors.map { |err| "- #{err}" }.join("\n"))
        raise KubernetesDeploy::TaskConfigurationError
      end
    end

    def kubeclient
      @kubeclient ||= kubeclient_builder.build_v1_kubeclient(@context)
    end

    def kubectl
      @kubectl ||= Kubectl.new(namespace: @namespace, context: @context, logger: @logger, log_failure_by_default: true)
    end

    def v1beta1_kubeclient
      @v1beta1_kubeclient ||= kubeclient_builder.build_v1beta1_kubeclient(@context)
    end

    def kubeclient_builder
      @kubeclient_builder ||= KubeclientBuilder.new
    end
  end
end
