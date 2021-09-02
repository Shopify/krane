# frozen_string_literal: true
require 'krane/common'
require 'krane/kubernetes_resource'
require 'krane/kubernetes_resource/deployment'
require 'krane/kubeclient_builder'
require 'krane/resource_watcher'
require 'krane/kubectl'

module Krane
  # Restart the pods in one or more deployments
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

    RESTART_TRIGGER_ANNOTATION = "kubectl.kubernetes.io/restartedAt"

    attr_reader :task_config

    delegate :kubeclient_builder, to: :task_config

    # Initializes the restart task
    #
    # @param context [String] Kubernetes context / cluster (*required*)
    # @param namespace [String] Kubernetes namespace (*required*)
    # @param logger [Object] Logger object (defaults to an instance of Krane::FormattedLogger)
    # @param global_timeout [Integer] Timeout in seconds
    def initialize(context:, namespace:, logger: nil, global_timeout: nil, kubeconfig: nil)
      @logger = logger || Krane::FormattedLogger.build(namespace, context)
      @task_config = Krane::TaskConfig.new(context, namespace, @logger, kubeconfig)
      @context = context
      @namespace = namespace
      @global_timeout = global_timeout
    end

    # Runs the task, returning a boolean representing success or failure
    #
    # @return [Boolean]
    def run(**args)
      perform!(**args)
      true
    rescue FatalDeploymentError
      false
    end
    alias_method :perform, :run

    # Runs the task, raising exceptions in case of issues
    #
    # @param deployments [Array<String>] Array of workload names to restart
    # @param selector [Hash] Selector(s) parsed by Krane::LabelSelector
    # @param verify_result [Boolean] Wait for completion and verify success
    #
    # @return [nil]
    def run!(deployments: [], statefulsets: [], daemonsets: [], selector: nil, verify_result: true)
      start = Time.now.utc
      @logger.reset

      @logger.phase_heading("Initializing restart")
      verify_config!
      deployments, statefulsets, daemonsets = identify_target_workloads(deployments, statefulsets,
                                                daemonsets, selector: selector)

      @logger.phase_heading("Triggering restart by touching ENV[RESTARTED_AT]")
      patch_kubeclient_deployments(deployments)
      patch_kubeclient_statefulsets(statefulsets)
      patch_kubeclient_daemonsets(daemonsets)

      if verify_result
        @logger.phase_heading("Waiting for rollout")
        resources = build_watchables(deployments, start, Deployment)
        resources += build_watchables(statefulsets, start, StatefulSet)
        resources += build_watchables(daemonsets, start, DaemonSet)
        verify_restart(resources)
      else
        warning = "Result verification is disabled for this task"
        @logger.summary.add_paragraph(ColorizedString.new(warning).yellow)
      end
      StatsD.client.distribution('restart.duration', StatsD.duration(start), tags: tags('success', deployments))
      @logger.print_summary(:success)
    rescue DeploymentTimeoutError
      StatsD.client.distribution('restart.duration', StatsD.duration(start), tags: tags('timeout', deployments))
      @logger.print_summary(:timed_out)
      raise
    rescue FatalDeploymentError => error
      StatsD.client.distribution('restart.duration', StatsD.duration(start), tags: tags('failure', deployments))
      @logger.summary.add_action(error.message) if error.message != error.class.to_s
      @logger.print_summary(:failure)
      raise
    end
    alias_method :perform!, :run!

    private

    def tags(status, deployments)
      %W(namespace:#{@namespace} context:#{@context} status:#{status} deployments:#{deployments.to_a.length}})
    end

    def identify_target_workloads(deployment_names, statefulset_names, daemonset_names, selector: nil)
      if deployment_names.blank? && statefulset_names.blank? && daemonset_names.blank?
        if selector.nil?
          @logger.info("Configured to restart all workloads with the `#{ANNOTATION}` annotation")
        else
          @logger.info(
            "Configured to restart all workloads with the `#{ANNOTATION}` annotation and #{selector} selector"
          )
        end
        deployments = identify_target_deployments(selector: selector)
        statefulsets = identify_target_statefulsets(selector: selector)
        daemonsets = identify_target_daemonsets(selector: selector)

        if deployments.none? && statefulsets.none? && daemonsets.none?
          raise FatalRestartError, "no deployments, statefulsets, or daemonsets, with the `#{ANNOTATION}` " \
            "annotation found in namespace #{@namespace}"
        end
      elsif deployment_names.empty? && statefulset_names.empty? && daemonset_names.empty?
        raise FatalRestartError, "Configured to restart workloads by name, but list of names was blank"
      elsif !selector.nil?
        raise FatalRestartError, "Can't specify workload names and selector at the same time"
      else
        deployments, statefulsets, daemonsets = identify_target_workloads_by_name(deployment_names,
            statefulset_names, daemonset_names)
        if deployments.none? && statefulsets.none? && daemonsets.none?
          error_msgs = []
          error_msgs << "no deployments with names #{list} found in namespace #{@namespace}" if deployment_names
          error_msgs << "no statefulsets with names #{list} found in namespace #{@namespace}" if statefulset_names
          error_msgs << "no daemonsets with names #{list} found in namespace #{@namespace}" if daemonset_names
          raise FatalRestartError, error_msgs.join(', ')
        end
      end
      [deployments, statefulsets, daemonsets]
    end

    def identify_target_workloads_by_name(deployment_names, statefulset_names, daemonset_names)
      deployment_names = deployment_names.uniq
      statefulset_names = statefulset_names.uniq
      daemonset_names = daemonset_names.uniq

      if deployment_names.present?
        @logger.info("Configured to restart deployments by name: #{deployment_names.join(', ')}")
      end
      if statefulset_names.present?
        @logger.info("Configured to restart statefulsets by name: #{statefulset_names.join(', ')}")
      end
      if daemonset_names.present?
        @logger.info("Configured to restart daemonsets by name: #{daemonset_names.join(', ')}")
      end

      [fetch_deployments(deployment_names), fetch_statefulsets(statefulset_names), fetch_daemonsets(daemonset_names)]
    end

    def identify_target_deployments(selector: nil)
      deployments = if selector.nil?
        apps_v1_kubeclient.get_deployments(namespace: @namespace)
      else
        selector_string = selector.to_s
        apps_v1_kubeclient.get_deployments(namespace: @namespace, label_selector: selector_string)
      end
      deployments.select { |d| d.metadata.annotations[ANNOTATION] }
    end

    def identify_target_statefulsets(selector: nil)
      statefulsets = if selector.nil?
        apps_v1_kubeclient.get_stateful_sets(namespace: @namespace)
      else
        selector_string = selector.to_s
        apps_v1_kubeclient.get_stateful_sets(namespace: @namespace, label_selector: selector_string)
      end
      statefulsets.select { |d| d.metadata.annotations[ANNOTATION] }
    end

    def identify_target_daemonsets(selector: nil)
      daemonsets = if selector.nil?
        apps_v1_kubeclient.get_daemon_sets(namespace: @namespace)
      else
        selector_string = selector.to_s
        apps_v1_kubeclient.get_daemon_sets(namespace: @namespace, label_selector: selector_string)
      end
      daemonsets.select { |d| d.metadata.annotations[ANNOTATION] }
    end

    def build_watchables(kubeclient_resources, started, klass)
      kubeclient_resources.map do |d|
        definition = d.to_h.deep_stringify_keys
        r = klass.new(namespace: @namespace, context: @context, definition: definition, logger: @logger)
        r.deploy_started_at = started # we don't care what happened to the resource before the restart cmd ran
        r
      end
    end

    def patch_deployment_with_restart(record)
      apps_v1_kubeclient.patch_deployment(
        record.metadata.name,
        build_patch_payload(record),
        @namespace
      )
    end

    def patch_statefulset_with_restart(record)
      apps_v1_kubeclient.patch_stateful_set(
        record.metadata.name,
        build_patch_payload(record),
        @namespace
      )
    end

    def patch_daemonset_with_restart(record)
      apps_v1_kubeclient.patch_daemon_set(
        record.metadata.name,
        build_patch_payload(record),
        @namespace
      )
    end

    def patch_kubeclient_deployments(deployments)
      deployments.each do |record|
        begin
          patch_deployment_with_restart(record)
          @logger.info("Triggered `Deployment/#{record.metadata.name}` restart")
        rescue Kubeclient::HttpError => e
          raise RestartAPIError.new(record.metadata.name, e.message)
        end
      end
    end

    def patch_kubeclient_statefulsets(statefulsets)
      statefulsets.each do |record|
        begin
          patch_statefulset_with_restart(record)
          @logger.info("Triggered `StatefulSet/#{record.metadata.name}` restart")
        rescue Kubeclient::HttpError => e
          raise RestartAPIError.new(record.metadata.name, e.message)
        end
      end
    end

    def patch_kubeclient_daemonsets(daemonsets)
      daemonsets.each do |record|
        begin
          patch_daemonset_with_restart(record)
          @logger.info("Triggered `DaemonSet/#{record.metadata.name}` restart")
        rescue Kubeclient::HttpError => e
          raise RestartAPIError.new(record.metadata.name, e.message)
        end
      end
    end

    def fetch_deployments(list)
      list.map do |name|
        record = nil
        begin
          record = apps_v1_kubeclient.get_deployment(name, @namespace)
        rescue Kubeclient::ResourceNotFoundError
          raise FatalRestartError, "Deployment `#{name}` not found in namespace `#{@namespace}`"
        end
        record
      end
    end

    def fetch_statefulsets(list)
      list.map do |name|
        record = nil
        begin
          record = apps_v1_kubeclient.get_stateful_set(name, @namespace)
        rescue Kubeclient::ResourceNotFoundError
          raise FatalRestartError, "StatefulSet `#{name}` not found in namespace `#{@namespace}`"
        end
        record
      end
    end

    def fetch_daemonsets(list)
      list.map do |name|
        record = nil
        begin
          record = apps_v1_kubeclient.get_daemon_set(name, @namespace)
        rescue Kubeclient::ResourceNotFoundError
          raise FatalRestartError, "DaemonSet `#{name}` not found in namespace `#{@namespace}`"
        end
        record
      end
    end

    def build_patch_payload(deployment)
      {
        spec: {
          template: {
            metadata: {
              annotations: {
                RESTART_TRIGGER_ANNOTATION => Time.now.utc.to_datetime.rfc3339
              }
            }
          }
        }
      }
    end

    def verify_restart(resources)
      ResourceWatcher.new(resources: resources, operation_name: "restart",
        timeout: @global_timeout, task_config: @task_config).run
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
        raise Krane::TaskConfigurationError
      end
    end

    def apps_v1_kubeclient
      @apps_v1_kubeclient ||= kubeclient_builder.build_apps_v1_kubeclient(@context)
    end

    def kubeclient
      @kubeclient ||= kubeclient_builder.build_v1_kubeclient(@context)
    end

    def kubectl
      @kubectl ||= Kubectl.new(task_config: @task_config, log_failure_by_default: true)
    end

    def v1beta1_kubeclient
      @v1beta1_kubeclient ||= kubeclient_builder.build_v1beta1_kubeclient(@context)
    end
  end
end
