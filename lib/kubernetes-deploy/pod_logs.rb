# frozen_string_literal: true
module KubernetesDeploy
  class PodLogs
    def initialize(logger:, pod_name:, container_names:)
      @logger = logger
      @pod_name = pod_name
      @container_names = container_names
      @last_timestamp_seen_for_container = {}
      @container_logs = Hash.new { |hash, key| hash[key] = [] }
    end

    def sync(kubectl)
      latest_logs = fetch_logs(kubectl, since: @last_timestamp_seen_for_container.values.min)
      latest_logs.each do |container_name, log_lines|
        next if log_lines.empty?

        log_lines.each do |line|
          timestamp, msg = split_timestamped_line(line)
          next if likely_duplicate?(timestamp, container_name)
          @container_logs[container_name] << msg
          @last_timestamp_seen_for_container[container_name] = timestamp
        end
      end
    end

    def print_latest
      @last_printed_indexes ||= Hash.new { |hash, key| hash[key] = -1 }
      @container_logs.each do |container_name, logs|
        prefix = "[#{container_name}]  " if @container_names.length > 1
        start_at = @last_printed_indexes[container_name] + 1
        logs[start_at..-1].each do |line|
          @logger.info "#{prefix}#{line}"
        end
        @last_printed_indexes[container_name] = logs.length - 1
      end
    end

    def print_all(prevent_duplicate: true)
      return if @already_displayed && prevent_duplicate

      if @container_logs.values.all?(&:empty?)
        @logger.warn("No logs found for pod #{@pod_name}")
        return
      end

      @container_logs.each do |container_name, logs|
        if logs.blank?
          @logger.warn("No logs found for container '#{container_name}'")
        else
          @logger.blank_line
          @logger.info("Logs from pod/#{@pod_name} container '#{container_name}':")
          logs.each { |line| @logger.info("\t#{line}") }
          @logger.blank_line
        end
      end

      @already_displayed = true
    end

    def to_h
      @container_logs.dup
    end

    private

    def likely_duplicate?(timestamp, container_name)
      return false unless @last_timestamp_seen_for_container[container_name] && timestamp
      # The --since-time granularity the API server supports is not adequate to prevent duplicates
      # This comparison takes the fractional seconds into account
      timestamp <= @last_timestamp_seen_for_container[container_name]
    end

    def fetch_logs(kubectl, since: nil)
      @container_names.each_with_object({}) do |container_name, container_logs|
        cmd = [
          "logs",
          @pod_name,
          "--container=#{container_name}",
          "--timestamps"
        ]
        cmd << "--since-time=#{since.to_datetime.rfc3339}" if since.present?

        out, _err, _st = kubectl.run(*cmd, log_failure: false)
        container_logs[container_name] = out.split("\n")
      end
    end

    def split_timestamped_line(log_line)
      timestamp, message = log_line.split(" ", 2)
      [Time.parse(timestamp), message]
    rescue ArgumentError
      nil
    end
  end
end
