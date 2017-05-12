# frozen_string_literal: true
require 'kubernetes-deploy/kubeclient_builder'
require 'kubernetes-deploy/resource_watcher'

module KubernetesDeploy
  class RestartTask
    include KubernetesDeploy::KubeclientBuilder

    class DeploymentNotFoundError < FatalDeploymentError
      def initialize(name, namespace)
        super("Deployment `#{name}` not found in namespace `#{namespace}`. Aborting the task.")
      end
    end

    class RestartError < FatalDeploymentError
      def initialize(deployment_name, response)
        super("Failed to restart #{deployment_name}. " \
            "API returned non-200 response code (#{response.code})\n" \
            "Response:\n#{response.body}")
      end
    end

    HTTP_OK_RANGE = 200..299
    ANNOTATION = "shipit.shopify.io/restart"

    def initialize(context:, namespace:, logger:)
      @context = context
      @namespace = namespace
      @logger = logger
      @kubeclient = build_v1_kubeclient(context)
      @v1beta1_kubeclient = build_v1beta1_kubeclient(context)
      @policy_v1beta1_kubeclient = build_policy_v1beta1_kubeclient(context)
    end

    def perform(deployments_names = nil)
      @logger.reset
      verify_namespace

      if deployments_names
        deployments = fetch_deployments(deployments_names.uniq)

        if deployments.none?
          raise ArgumentError, "no deployments with names #{deployments_names} found in namespace #{@namespace}"
        end
      else
        deployments = @v1beta1_kubeclient
          .get_deployments(namespace: @namespace)
          .select { |d| d.metadata.annotations[ANNOTATION] }

        if deployments.none?
          raise ArgumentError, "no deployments found in namespace #{@namespace} with #{ANNOTATION} annotation available"
        end
      end

      @logger.phase_heading("Triggering restart by touching ENV[RESTARTED_AT]")
      patch_kubeclient_deployments(deployments)

      @logger.phase_heading("Waiting for rollout")
      wait_for_rollout(deployments)

      names = deployments.map { |d| "`#{d.metadata.name}`" }
      @logger.info "Restart of #{names.sort.join(', ')} deployments succeeded"
      true
    rescue FatalDeploymentError => error
      @logger.fatal "#{error.class}: #{error.message}"
      false
    end

    private

    def wait_for_rollout(kubeclient_resources)
      resources = kubeclient_resources.map do |d|
        Deployment.new(name: d.metadata.name, namespace: @namespace, context: @context, file: nil, logger: @logger)
      end
      watcher = ResourceWatcher.new(resources, logger: @logger)
      watcher.run
    end

    def verify_namespace
      @kubeclient.get_namespace(@namespace)
    rescue KubeException => error
      if error.error_code == 404
        raise NamespaceNotFoundError.new(@namespace, @context)
      else
        raise
      end
    end

    def patch_deployment_with_restart(record)
      @v1beta1_kubeclient.patch_deployment(
        record.metadata.name,
        build_patch_payload(record),
        @namespace
      )
    end

    def patch_kubeclient_deployments(deployments)
      deployments.each do |record|
        response = patch_deployment_with_restart(record)
        if HTTP_OK_RANGE.cover?(response.code)
          @logger.info "Triggered `#{record.metadata.name}` restart"
        else
          raise RestartError.new(record.metadata.name, response)
        end
      end
    end

    def fetch_deployments(list)
      list.map do |name|
        record = nil
        begin
          record = @v1beta1_kubeclient.get_deployment(name, @namespace)
        rescue KubeException => error
          if error.error_code == 404
            raise DeploymentNotFoundError.new(name, @namespace)
          else
            raise
          end
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
                  env: [{ name: "RESTARTED_AT", value: Time.now.to_i.to_s }]
                }
              end
            }
          }
        }
      }
    end
  end
end
