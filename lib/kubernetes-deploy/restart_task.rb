# frozen_string_literal: true
require 'kubernetes-deploy/kubeclient_builder'
require 'kubernetes-deploy/ui_helpers'
require 'kubernetes-deploy/resource_watcher'

module KubernetesDeploy
  class RestartTask
    include UIHelpers
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

    def initialize(context:, namespace:, logger: KubernetesDeploy.logger)
      @context = context
      @namespace = namespace
      @logger = logger
      @kubeclient = build_v1_kubeclient(context)
      @v1beta1_kubeclient = build_v1beta1_kubeclient(context)
    end

    def perform(deployments_names)
      verify_namespace

      if deployments_names.empty?
        raise ArgumentError, "#perform takes at least one deployment to restart"
      end

      if deployments_names == "all"
        deployments_names = @v1beta1_kubeclient.get_deployments(namespace: @namespace).map { |d| d.metadata.name }
        raise ArgumentError, "no deployments found in namespace #{@namespace}" if deployments_names.none?
      end

      phase_heading("Triggering restart by touching ENV[RESTARTED_AT]")
      deployments = fetch_deployments(deployments_names.uniq)
      patch_kubeclient_deployments(deployments)

      phase_heading("Waiting for rollout")
      wait_for_rollout(deployments)

      names = deployments.map { |d| "`#{d.metadata.name}`" }
      @logger.info "Restart of #{names.sort.join(', ')} deployments succeeded"
    end

    private

    def wait_for_rollout(kubeclient_resources)
      resources = kubeclient_resources.map { |d| Deployment.new(d.metadata.name, @namespace, @context, nil) }
      watcher = ResourceWatcher.new(resources)
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
