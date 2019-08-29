# frozen_string_literal: true

require 'kubernetes-deploy/concurrency'
require 'kubernetes-deploy/resource_cache'

module KubernetesDeploy
  class ResourceWatcher
    extend KubernetesDeploy::StatsD::MeasureMethods

    def initialize(resources:, logger:, context:, namespace:,
      deploy_started_at: Time.now.utc, operation_name: "deploy", timeout: nil, sha: nil)
      unless resources.is_a?(Enumerable)
        raise ArgumentError, <<~MSG
          ResourceWatcher expects Enumerable collection, got `#{resources.class}` instead
        MSG
      end
      @resources = resources
      @logger = logger
      @namespace = namespace
      @context = context
      @deploy_started_at = deploy_started_at
      @operation_name = operation_name
      @timeout = timeout
      @sha = sha
    end

    def run(delay_sync: 3.seconds, reminder_interval: 30.seconds, record_summary: true)
      last_message_logged_at = monitoring_started = Time.now.utc
      remainder = @resources.dup

      while remainder.present?
        report_and_give_up(remainder) if global_timeout?(monitoring_started)
        sleep_until_next_sync(delay_sync)

        sync_resources(remainder)

        new_successes, remainder = remainder.partition(&:deploy_succeeded?)
        new_failures, remainder = remainder.partition(&:deploy_failed?)
        new_timeouts, remainder = remainder.partition(&:deploy_timed_out?)

        if new_successes.present? || new_failures.present? || new_timeouts.present?
          report_what_just_happened(new_successes, new_failures, new_timeouts)
          report_what_is_left(remainder, reminder: false)
          last_message_logged_at = Time.now.utc
        elsif due_for_reminder?(last_message_logged_at, reminder_interval)
          report_what_is_left(remainder, reminder: true)
          last_message_logged_at = Time.now.utc
        end
      end
      record_statuses_for_summary(@resources) if record_summary
    end

    private

    def sync_resources(resources)
      cache = ResourceCache.new(@namespace, @context, @logger)
      KubernetesDeploy::Concurrency.split_across_threads(resources) { |r| r.sync(cache) }
      resources.each(&:after_sync)
    end
    measure_method(:sync_resources, "sync.duration")

    def statsd_tags
      {
        namespace: @namespace,
        context: @context,
        sha: @sha,
      }
    end

    def global_timeout?(started_at)
      @timeout && (Time.now.utc - started_at > @timeout)
    end

    def sleep_until_next_sync(min_interval)
      @next_sync_time ||= Time.now.utc
      if (sleep_duration = @next_sync_time - Time.now.utc) > 0
        sleep(sleep_duration)
      end
      @next_sync_time = Time.now.utc + min_interval
    end

    def report_what_just_happened(new_successes, new_failures, new_timeouts)
      watch_time = (Time.now.utc - @deploy_started_at).round(1)
      new_failures.each do |resource|
        resource.report_status_to_statsd(watch_time)
        @logger.error("#{resource.id} failed to #{@operation_name} after #{watch_time}s")
      end

      new_timeouts.each do |resource|
        resource.report_status_to_statsd(watch_time)
        @logger.error("#{resource.id} rollout timed out after #{watch_time}s")
      end

      if new_successes.present?
        new_successes.each { |r| r.report_status_to_statsd(watch_time) }
        success_string = ColorizedString.new("Successfully #{past_tense_operation} in #{watch_time}s:").green
        @logger.info("#{success_string} #{new_successes.map(&:id).join(', ')}")
      end
    end

    def report_what_is_left(resources, reminder:)
      return unless resources.present?
      resource_list = resources.map(&:id).join(', ')
      msg = reminder ? "Still waiting for: #{resource_list}" : "Continuing to wait for: #{resource_list}"
      @logger.info(msg)
    end

    def report_and_give_up(remaining_resources)
      successful_resources, failed_resources = (@resources - remaining_resources).partition(&:deploy_succeeded?)
      record_success_statuses(successful_resources)
      record_failed_statuses(failed_resources, remaining_resources)

      if failed_resources.present? && !failed_resources.all?(&:deploy_timed_out?)
        raise FatalDeploymentError
      else
        raise DeploymentTimeoutError
      end
    end

    def record_statuses_for_summary(resources)
      successful_resources, failed_resources = resources.partition(&:deploy_succeeded?)
      record_success_statuses(successful_resources)
      record_failed_statuses(failed_resources)
    end

    def record_failed_statuses(failed_resources, global_timeouts = [])
      fail_count = failed_resources.length + global_timeouts.length

      if fail_count > 0
        timeouts, failures = failed_resources.partition(&:deploy_timed_out?)
        timeouts += global_timeouts
        if timeouts.present?
          @logger.summary.add_action(
            "timed out waiting for #{timeouts.length} #{'resource'.pluralize(timeouts.length)} to #{@operation_name}"
          )
        end

        if failures.present?
          @logger.summary.add_action(
            "failed to #{@operation_name} #{failures.length} #{'resource'.pluralize(failures.length)}"
          )
        end

        kubectl = Kubectl.new(namespace: @namespace, context: @context, logger: @logger, log_failure_by_default: false)
        KubernetesDeploy::Concurrency.split_across_threads(failed_resources + global_timeouts) do |r|
          r.sync_debug_info(kubectl)
        end

        failed_resources.each { |r| @logger.summary.add_paragraph(r.debug_message) }
        global_timeouts.each { |r| @logger.summary.add_paragraph(r.debug_message(:gave_up, timeout: @timeout)) }
      end
    end

    def record_success_statuses(successful_resources)
      success_count = successful_resources.length
      if success_count > 0
        @logger.summary.add_action("successfully #{past_tense_operation} #{success_count} "\
          "#{'resource'.pluralize(success_count)}")
        final_statuses = successful_resources.map(&:pretty_status).join("\n")
        @logger.summary.add_paragraph("#{ColorizedString.new('Successful resources').green}\n#{final_statuses}")
      end
    end

    def due_for_reminder?(last_message_logged_at, reminder_interval)
      (last_message_logged_at.to_f + reminder_interval.to_f) <= Time.now.utc.to_f
    end

    def past_tense_operation
      @operation_name == "run" ? "ran" : "#{@operation_name}ed"
    end
  end
end
