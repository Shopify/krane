# frozen_string_literal: true
module KubernetesDeploy
  class ContainerLogStreamer
    include KubeclientBuilder

    class PodNotFoundError < KubernetesDeploy::FatalDeploymentError; end
    class LogTimeoutError < KubernetesDeploy::DeploymentTimeoutError; end
    class PodFailedError < KubernetesDeploy::FatalDeploymentError; end

    REMINDER_INTERVAL = 60.seconds

    def initialize(pod, container, context, logger, sync_mediator)
      @pod = pod
      @container = container
      @context = context
      @logger = logger
      @sync_mediator = sync_mediator
    end

    def run(timeout: 300, reminder_interval: 30)
      @finished = false
      progress_deadline = 30
      wait_until_exists(progress_deadline)
      stream_logs(timeout, reminder_interval)
    end

    private

    def stream_logs(timeout, reminder_interval)
      log_watcher = kubeclient.watch_pod_log(@pod.name, @pod.namespace, container: @container)
      pod_watcher = ResourceWatcher.new(resources: [@pod], sync_mediator: @sync_mediator, logger: @logger,
        deploy_started_at: Time.now.utc, operation_name: "run", timeout: timeout)

      th = Thread.new do
        pod_watcher.run(delay_sync: 3.seconds, reminder_interval: reminder_interval,
          record_summary: true, print_logs: false)
        @finished = true
        log_watcher.finish
        raise DeploymentTimeoutError, "Timed out watching pod logs" if @pod.deploy_timed_out?
        raise FatalDeploymentError if @pod.deploy_failed?
      end
      th.abort_on_exception = true

      log_watcher.each do |line|
        @logger.info line # not working??
      end
    rescue Kubeclient::HttpError, HTTP::StateError, HTTP::ConnectionError => e # ad hoc, not good
      if @finished
        nil
      elsif pod_exists? # this retries too much
        sleep 3
        retry
      else
        raise PodNotFoundError, "Encountered error #{e.message} and could not find pod"
      end
    end

    def wait_until_exists(progress_deadline)
      first_look = Time.now.utc
      until timed_out?(first_look, progress_deadline)
        sleep 1
        return if pod_exists?
      end

      raise PodNotFoundError, "Pod still didn't exist after #{progress_deadline} seconds"
    end

    def pod_exists?
      kubeclient.get_pod(@pod.name, @pod.namespace)
      true
    rescue Kubeclient::ResourceNotFoundError
      false
    end

    def timed_out?(start_time, timeout)
      Time.now.utc - start_time >= timeout
    end

    def kubeclient
      @kubeclient ||= build_v1_kubeclient(@context)
    end
  end
end
