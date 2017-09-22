# frozen_string_literal: true
module KubernetesDeploy
  class ResourceWatcher
    def initialize(resources, logger:, deploy_started_at: Time.now.utc, operation_name: "deploy")
      unless resources.is_a?(Enumerable)
        raise ArgumentError, <<~MSG
          ResourceWatcher expects Enumerable collection, got `#{resources.class}` instead
        MSG
      end
      @resources = resources
      @logger = logger
      @deploy_started_at = deploy_started_at
      @operation_name = operation_name
    end

    def run(delay_sync: 3.seconds, reminder_interval: 30.seconds, record_summary: true)
      delay_sync_until = last_message_logged_at = Time.now.utc
      remainder = @resources.dup

      while remainder.present?
        if Time.now.utc < delay_sync_until
          sleep(delay_sync_until - Time.now.utc)
        end
        delay_sync_until = Time.now.utc + delay_sync # don't pummel the API if the sync is fast

        KubernetesDeploy::Concurrency.split_across_threads(remainder, &:sync)
        newly_finished_resources, remainder = remainder.partition(&:deploy_finished?)

        if newly_finished_resources.present?
          watch_time = (Time.now.utc - @deploy_started_at).round(1)
          report_what_just_happened(newly_finished_resources, watch_time)
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

    def report_what_just_happened(resources, watch_time)
      resources.each { |r| r.report_status_to_statsd(watch_time) }

      new_successes, new_failures = resources.partition(&:deploy_succeeded?)
      new_failures.each do |resource|
        if resource.deploy_failed?
          @logger.error("#{resource.id} failed to #{@operation_name} after #{watch_time}s")
        else
          @logger.error("#{resource.id} rollout timed out")
        end
      end

      if new_successes.present?
        success_string = ColorizedString.new("Successfully #{@operation_name}ed in #{watch_time}s:").green
        @logger.info("#{success_string} #{new_successes.map(&:id).join(', ')}")
      end
    end

    def report_what_is_left(resources, reminder:)
      return unless resources.present?
      resource_list = resources.map(&:id).join(', ')
      msg = reminder ? "Still waiting for: #{resource_list}" : "Continuing to wait for: #{resource_list}"
      @logger.info(msg)
    end

    def record_statuses_for_summary(resources)
      successful_resources, failed_resources = resources.partition(&:deploy_succeeded?)
      fail_count = failed_resources.length
      success_count = successful_resources.length

      if success_count > 0
        @logger.summary.add_action("successfully #{@operation_name}ed #{success_count} "\
          "#{'resource'.pluralize(success_count)}")
        final_statuses = successful_resources.map(&:pretty_status).join("\n")
        @logger.summary.add_paragraph("#{ColorizedString.new('Successful resources').green}\n#{final_statuses}")
      end

      if fail_count > 0
        @logger.summary.add_action("failed to #{@operation_name} #{fail_count} #{'resource'.pluralize(fail_count)}")
        failed_resources.each { |r| @logger.summary.add_paragraph(r.debug_message) }
      end
    end

    def due_for_reminder?(last_message_logged_at, reminder_interval)
      (last_message_logged_at.to_f + reminder_interval.to_f) <= Time.now.utc.to_f
    end
  end
end
