# frozen_string_literal: true
module KubernetesDeploy
  class PodLogRetriever
    MIN_STREAM_PRINT_INTERVAL = 30.seconds

    def initialize(logger:, pod_name:, container_names:)
      @logger = logger
      @pod_name = pod_name
      @container_names = container_names
      @last_timestamp_printed = nil
      @last_printed_stream = nil
    end

    def print_all(kubectl:, since:, prevent_duplicate:)
      return if @already_displayed && prevent_duplicate
      container_logs = fetch_logs(kubectl, since: since)

      if container_logs.empty?
        @logger.warn("No logs found for pod #{@pod_name}")
        return
      end

      container_logs.each do |container_identifier, logs|
        if logs.blank?
          @logger.warn("No logs found for container '#{container_identifier}'")
        else
          @logger.blank_line
          @logger.info("Logs from pod/#{@pod_name} container '#{container_identifier}':")
          logs.each { |line| @logger.info("\t#{line}") }
          @logger.blank_line
        end
      end

      @already_displayed = true
    end

    def print_latest(kubectl:)
      container_logs = fetch_logs(kubectl, since: @last_timestamp_printed, timestamps: true)

      last_timestamps = []
      container_logs.each do |container_name, log_lines|
        next if log_lines.empty?

        log_lines.each do |line|
          timestamp, msg = split_timestamped_line(line)
          if @last_timestamp_printed && timestamp
            # The --since-time granularity the API server supports is not adequate to prevent duplicates
            # This comparison takes the fractional seconds into account
            next if timestamp <= @last_timestamp_printed
          end
          @logger.info("  [#{container_name}]  #{msg}")
        end

        @last_printed_from_stream = Time.now.utc
        last_timestamps << split_timestamped_line(log_lines.last).first
      end

      @last_timestamp_printed = last_timestamps.max
      if should_print_reminder?
        @logger.info("Waiting for more logs from pod")
      end
    end

    def fetch_logs(kubectl, since: nil, timestamps: false, tail_limit: nil)
      @container_names.each_with_object({}) do |container_name, container_logs|
        cmd = [
          "logs",
          @pod_name,
          "--container=#{container_name}",
        ]
        cmd << "--since-time=#{since.to_datetime.rfc3339}" if since.present?
        cmd << "--tail=#{tail_limit}" if tail_limit
        cmd << "--timestamps" if timestamps
        out, _err, _st = kubectl.run(*cmd, log_failure: false)
        container_logs[container_name] = out.split("\n")
      end
    end

    private

    def should_print_reminder?
      return false unless @last_printed_from_stream
      (Time.now.utc - @last_printed_from_stream) > MIN_STREAM_PRINT_INTERVAL
    end

    def split_timestamped_line(log_line)
      timestamp, message = log_line.split(" ", 2)
      [Time.parse(timestamp), message]
    rescue ArgumentError
      nil
    end
  end
end
