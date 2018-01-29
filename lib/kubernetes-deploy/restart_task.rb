# frozen_string_literal: true
require 'kubernetes-deploy/kubeclient_builder'
require 'kubernetes-deploy/resource_watcher'
require 'kubernetes-deploy/kubectl'

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

    def initialize(context:, namespace:, logger:)
      @context = context
      @namespace = namespace
      @logger = logger
    end

    # Perform a restart of Kubernetes Deployments.
    #
    # deployments is a list of deployment names.
    # selector is a kubernetes selector, as a hash.
    # Only one of them can be specified.
    def perform(deployments: nil, selector: nil)
      start = Time.now.utc
      @logger.reset

      @logger.phase_heading("Initializing restart")
      verify_namespace
      kubernetes_deployments = identify_target_deployments(deployments, selector)

      if kubectl.server_version < Gem::Version.new(MIN_KUBE_VERSION)
        @logger.warn(KubernetesDeploy::Errors.server_version_warning(kubectl.server_version))
      end
      @logger.phase_heading("Triggering restart by touching ENV[RESTARTED_AT]")
      patch_kubeclient_deployments(kubernetes_deployments)

      @logger.phase_heading("Waiting for rollout")
      resources = build_watchables(kubernetes_deployments, start)
      ResourceWatcher.new(resources, logger: @logger, operation_name: "restart").run
      success = resources.all?(&:deploy_succeeded?)
    rescue FatalDeploymentError => error
      @logger.summary.add_action(error.message)
      success = false
    ensure
      @logger.print_summary(success)
      status = success ? "success" : "failed"
      tags = %W(namespace:#{@namespace} context:#{@context} status:#{status} deployments:#{deployments.to_a.length}})
      ::StatsD.measure('restart.duration', StatsD.duration(start), tags: tags)
    end

    private

    def identify_target_deployments(deployment_names, selector)
      if deployment_names.nil?
        deployments = if selector.nil?
          @logger.info("Configured to restart all deployments with the `#{ANNOTATION}` annotation")
          v1beta1_kubeclient.get_deployments(namespace: @namespace)
        else
          selector_string = Utils.selector_to_string(selector)
          @logger.info("Configured to restart all deployments with the `#{ANNOTATION}` annotation and #{selector_string} selector")
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

    def verify_namespace
      kubeclient.get_namespace(@namespace)
      @logger.info("Namespace #{@namespace} found in context #{@context}")
    rescue KubeException => error
      if error.error_code == 404
        raise NamespaceNotFoundError.new(@namespace, @context)
      else
        raise
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
        response = patch_deployment_with_restart(record)
        if HTTP_OK_RANGE.cover?(response.code)
          @logger.info "Triggered `#{record.metadata.name}` restart"
        else
          raise RestartAPIError.new(record.metadata.name, response)
        end
      end
    end

    def fetch_deployments(list)
      list.map do |name|
        record = nil
        begin
          record = v1beta1_kubeclient.get_deployment(name, @namespace)
        rescue KubeException => error
          if error.error_code == 404
            raise FatalRestartError, "Deployment `#{name}` not found in namespace `#{@namespace}`"
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

    def kubeclient
      @kubeclient ||= build_v1_kubeclient(@context)
    end

    def kubectl
      @kubectl ||= Kubectl.new(namespace: @namespace, context: @context, logger: @logger, log_failure_by_default: true)
    end

    def v1beta1_kubeclient
      @v1beta1_kubeclient ||= build_v1beta1_kubeclient(@context)
    end
  end
end
