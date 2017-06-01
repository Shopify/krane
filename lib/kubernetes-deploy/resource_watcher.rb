# frozen_string_literal: true
module KubernetesDeploy
  class ResourceWatcher
    def initialize(resources, logger:)
      unless resources.is_a?(Enumerable)
        raise ArgumentError, <<-MSG.strip
ResourceWatcher expects Enumerable collection, got `#{resources.class}` instead
MSG
      end
      @resources = resources
      @logger = logger
    end

    def run(delay_sync: 3.seconds)
      delay_sync_until = Time.now.utc
      started_at = delay_sync_until

      while @resources.present?
        if Time.now.utc < delay_sync_until
          sleep(delay_sync_until - Time.now.utc)
        end
        watch_time = (Time.now.utc - started_at).round(1)
        delay_sync_until = Time.now.utc + delay_sync # don't pummel the API if the sync is fast
        @resources.each(&:sync)
        newly_finished_resources, @resources = @resources.partition(&:deploy_finished?)

        new_success_list = []
        newly_finished_resources.each do |resource|
          if resource.deploy_failed?
            @logger.error("#{resource.id} failed to deploy after #{watch_time}s")
          elsif resource.deploy_timed_out?
            @logger.error("#{resource.id} deployment timed out")
          else
            new_success_list << resource.id
          end
        end

        unless new_success_list.empty?
          success_string = ColorizedString.new("Successfully deployed in #{watch_time}s:").green
          @logger.info("#{success_string} #{new_success_list.join(', ')}")
        end

        if newly_finished_resources.present? && @resources.present? # something happened this cycle, more to go
          @logger.info("Continuing to wait for: #{@resources.map(&:id).join(', ')}")
        end
      end
    end
  end
end
