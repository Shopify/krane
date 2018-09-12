# frozen_string_literal: true
module KubernetesDeploy
  class ResourceReportingWatcher

    def initialize(resource:, logger:, timeout: nil)
      @resource = resource
      @logger = logger
      @sync_mediator = SyncMediator.new(namespace: @resource.namespace, context: @resource.context, logger: @logger)
      @timeout = timeout
    end

    def run(sync_interval: 5.seconds)
      last_loop_time = last_log_time = @resource.deploy_started_at
      @logger.info("Logs from #{@resource.id}:")

      loop do
        @resource.sync(@sync_mediator)
        last_log_time = print_resource_logs(last_log_time)
        break if deploy_ended?

        if (sleep_duration = sync_interval - (Time.now.utc - last_loop_time)) > 0
          sleep(sleep_duration)
        end
        last_loop_time = Time.now.utc
      end

      report_final_status
      raise_if_failed
    end

    private

    def print_resource_logs(last_log_time)
      logs = @resource.fetch_logs(@sync_mediator.kubectl, since: last_log_time)
      last_log_time = Time.now.utc

      logs.each do |_, log|
        if log.present?
          @logger.info("\t" + log.join("\n\t"))
        else
          @logger.info("\t...")
        end
      end

      last_log_time
    end

    def deploy_ended?
      @resource.deploy_succeeded? || @resource.deploy_failed? || @resource.deploy_timed_out? || global_timeout?
    end

    def global_timeout?
      @timeout.present? && Time.now.utc - @resource.deploy_started_at > @timeout
    end

    def report_final_status
      if @resource.deploy_failed? || @resource.deploy_timed_out?
        @logger.summary.add_paragraph(@resource.debug_message)
      elsif global_timeout?
        @logger.summary.add_paragraph(@resource.debug_message(:gave_up, timeout: @timeout))
      end
    end

    def raise_if_failed
      if @resource.deploy_failed?
        raise FatalDeploymentError, "Failed to deploy pod"
      elsif @resource.deploy_timed_out? || global_timeout?
        raise DeploymentTimeoutError
      end
    end
  end
end
