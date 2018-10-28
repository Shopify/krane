# frozen_string_literal: true
require 'kubernetes-deploy/kubeclient_builder'
require 'kubernetes-deploy/resource_watcher'

module KubernetesDeploy
  class RestartTask
    include KubernetesDeploy::KubeclientBuilder

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

    def initialize(context:, namespace:, logger:, max_watch_seconds: nil)
      @context = context
      @namespace = namespace
      @logger = logger
      @sync_mediator = SyncMediator.new(namespace: @namespace, context: @context, logger: @logger)
      @max_watch_seconds = max_watch_seconds
    end

    def perform(*args)
      perform!(*args)
      true
    rescue FatalDeploymentError
      false
    end

    def perform!(deployments_names = nil)
      start = Time.now.utc
      @logger.reset

      @logger.phase_heading("Initializing restart")
      config = validate_configuration(use_annotation: deployment_names.nil?, deployments_requested: deployments_names)

      @logger.phase_heading("Triggering restart by touching ENV[RESTARTED_AT]")
      restart_deployments(config.deployments)

      @logger.phase_heading("Waiting for rollout")
      watch_rollout(config.deployments, start)

      ::StatsD.measure('restart.duration', StatsD.duration(start), tags: tags('success', config.deployments))
      @logger.print_summary(:success)
    rescue DeploymentTimeoutError
      ::StatsD.measure('restart.duration', StatsD.duration(start), tags: tags('timeout', config.deployments))
      @logger.print_summary(:timed_out)
      raise
    rescue FatalDeploymentError => error
      ::StatsD.measure('restart.duration', StatsD.duration(start), tags: tags('failure', config.deployments))
      @logger.summary.add_action(error.message) if error.message != error.class.to_s
      @logger.print_summary(:failure)
      raise
    end

    private

    def tags(status, deployments)
      %W(namespace:#{@namespace} context:#{@context} status:#{status} deployments:#{deployments.to_a.length}})
    end

    def watch_rollout(deployments, start)
      resources = build_watchables(deployments, start)
      ResourceWatcher.new(resources: resources, sync_mediator: @sync_mediator,
        logger: @logger, operation_name: "restart", timeout: @max_watch_seconds).run
      failed_resources = resources.reject(&:deploy_succeeded?)
      success = failed_resources.empty?
      if !success && failed_resources.all?(&:deploy_timed_out?)
        raise DeploymentTimeoutError
      end
      raise FatalDeploymentError unless success
    end

    def build_watchables(kubeclient_resources, started)
      kubeclient_resources.map do |d|
        definition = d.to_h.deep_stringify_keys
        r = Deployment.new(namespace: @namespace, context: @context, definition: definition, logger: @logger)
        r.deploy_started_at = started # we don't care what happened to the resource before the restart cmd ran
        r
      end
    end

    def validate_configuration(**params)
      config = RestartTaskConfig.new(@context, @namespace, extra_config: params)
      unless config.valid?
        config.record_result(@logger)
        raise TaskConfigurationError, config.error_sentence
      end

      list = config.deployment_names.join(', ')
      if config.use_annotation?
        @logger.info("Configured to restart all deployments with the `#{ANNOTATION}` annotation, found: #{list}")
      else
        @logger.info("Configured to restart the following deployments: #{list}")
      end
      config
    end

    def patch_deployment_with_restart(record)
      v1beta1_kubeclient.patch_deployment(
        record.metadata.name,
        build_patch_payload(record),
        @namespace
      )
    end

    def restart_deployments(deployments)
      deployments.each do |record|
        begin
          patch_deployment_with_restart(record)
          @logger.info "Triggered `#{record.metadata.name}` restart"
        rescue Kubeclient::ResourceNotFoundError, Kubeclient::HttpError => e
          raise RestartAPIError.new(record.metadata.name, e.message)
        end
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
                  env: [{ name: "RESTARTED_AT", value: Time.now.to_i.to_s }]
                }
              end
            }
          }
        }
      }
    end

    def kubeclient
      @kubeclient ||= build_v1_kubeclient(@context)
    end

    def v1beta1_kubeclient
      @v1beta1_kubeclient ||= build_v1beta1_kubeclient(@context)
    end
  end
end
