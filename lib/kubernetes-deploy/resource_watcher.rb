# frozen_string_literal: true
module KubernetesDeploy
  class ResourceWatcher
    def initialize(resources)
      unless resources.is_a?(Enumerable)
        raise ArgumentError, <<-MSG.strip
ResourceWatcher expects Enumerable collection, got `#{resources.class}` instead
MSG
      end
      @resources = resources
    end

    def run(delay_sync: 3.seconds, logger: KubernetesDeploy.logger)
      delay_sync_until = Time.now.utc
      started_at = delay_sync_until
      human_resources = @resources.map(&:id).join(", ")
      max_wait_time = @resources.map(&:timeout).max
      logger.info("Waiting for #{human_resources} with #{max_wait_time}s timeout")

      while @resources.present?
        if Time.now.utc < delay_sync_until
          sleep(delay_sync_until - Time.now.utc)
        end
        delay_sync_until = Time.now.utc + delay_sync # don't pummel the API if the sync is fast
        @resources.each(&:sync)
        newly_finished_resources, @resources = @resources.partition(&:deploy_finished?)
        newly_finished_resources.each do |resource|
          next unless resource.deploy_failed? || resource.deploy_timed_out?
          logger.error("#{resource.id} failed to deploy with status '#{resource.status}'.")
        end
      end

      watch_time = Time.now.utc - started_at
      logger.info("Spent #{watch_time.round(2)}s waiting for #{human_resources}")
    end
  end
end
