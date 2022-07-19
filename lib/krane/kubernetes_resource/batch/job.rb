# frozen_string_literal: true
module Krane
  module Batch
    class Job < KubernetesResource
      TIMEOUT = 10.minutes

      def deploy_succeeded?
        # Don't block deploys for long running jobs,
        # Instead report success when there is at least 1 active
        return false unless deploy_started?
        done? || running?
      end

      def deploy_failed?
        return false unless deploy_started?
        return true if failed_status_condition
        return false unless @instance_data.dig("spec", "backoffLimit").present?
        (@instance_data.dig("status", "failed") || 0) >= @instance_data.dig("spec", "backoffLimit")
      end

      def status
        if !exists?
          super
        elsif done?
          "Succeeded"
        elsif running?
          "Started"
        elsif deploy_failed?
          "Failed"
        else
          "Unknown"
        end
      end

      def failure_message
        if (condition = failed_status_condition.presence)
          "#{condition['reason']} (#{condition['message']})"
        end
      end

      private

      def failed_status_condition
        @instance_data.dig("status", "conditions")&.detect do |condition|
          condition["type"] == 'Failed' && condition['status'] == "True"
        end
      end

      def done?
        (@instance_data.dig("status", "succeeded") || 0) == @instance_data.dig("spec", "completions")
      end

      def running?
        now = Time.now.utc
        start_time = @instance_data.dig("status", "startTime")
        # Wait 5 seconds to ensure job doesn't immediately fail.
        return false if !start_time.present? || now - Time.parse(start_time) < 5.second
        (@instance_data.dig("status", "active") || 0) >= 1
      end
    end
  end
end
