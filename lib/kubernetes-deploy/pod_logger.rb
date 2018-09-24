# frozen_string_literal: true
module KubernetesDeploy
  class PodLogger
    class << self
      def log(pod:, mediator:, logger:, stream: false)
        @logger = logger
        @pod = pod

        if stream
          stream_logs(mediator)
        elsif @pod.deploy_succeeded?
          display_logs(mediator)
        end
      end

      private

      def stream_logs(mediator)
        @logger.info("Logs from #{@pod.id}:") unless @last_log_fetch
        since = @last_log_fetch || @pod.deploy_started_at
        logs = @pod.fetch_logs(mediator.kubectl, since: since, timestamps: true)

        logs.each do |_, log|
          if log.present?
            ts_logs = log.map do |line|
              dt, message = line.split(" ", 2)
              [parse_date(dt), message]
            end
            ts_logs.select! { |dt, _| dt.nil? || dt > since }
            @logger.info("\t" + ts_logs.map(&:last).join("\n\t"))
            @last_log_fetch = ts_logs.last.first if ts_logs.last&.first
          else
            @logger.info("\t...")
          end
        end
      end

      def display_logs(mediator)
        return if @already_displayed
        container_logs = @pod.fetch_logs(mediator.kubectl)

        if container_logs.empty?
          @logger.warn("No logs found for pod #{id}")
          return
        end

        container_logs.each do |container_identifier, logs|
          if logs.blank?
            @logger.warn("No logs found for container '#{container_identifier}'")
          else
            @logger.blank_line
            @logger.info("Logs from #{@pod.id} container '#{container_identifier}':")
            logs.each { |line| @logger.info("\t#{line}") }
            @logger.blank_line
          end
        end

        @already_displayed = true
      end

      def parse_date(dt)
        DateTime.parse(dt)
      rescue ArgumentError
        nil
      end
    end
  end
end
