# frozen_string_literal: true
module KubernetesDeploy
  class PodLogger
    def initialize(stream:, logger:, pod_name:, pod_id:)
      @stream = stream
      @logger = logger
      @pod_name = pod_name
      @pod_id = pod_id
    end

    def log(kubectl:, deploy_succeeded:, deploy_started_at:, unmanaged:, container_names:)
      if unmanaged
        if @stream
          stream_logs(kubectl, deploy_started_at, unmanaged, container_names)
        elsif deploy_succeeded
          display_logs(kubectl, deploy_started_at, unmanaged, container_names)
        end
      end
    end

    def fetch_logs(kubectl, deploy_started_at:, container_names:, since: nil, timestamps: false, unmanaged:)
      container_names.each_with_object({}) do |container_name, container_logs|
        cmd = [
          "logs",
          @pod_name,
          "--container=#{container_name}",
          "--since-time=#{(since || deploy_started_at).to_datetime.rfc3339}",
        ]
        cmd << "--tail=#{KubernetesResource::LOG_LINE_COUNT}" unless unmanaged
        cmd << "--timestamps" if timestamps
        out, _err, _st = kubectl.run(*cmd, log_failure: false)
        container_logs[container_name] = out.split("\n")
      end
    end

    private

    def stream_logs(kubectl, deploy_started_at, unmanaged, container_names)
      @logger.info("Logs from #{@pod_id}:") unless @last_log_fetch
      since = @last_log_fetch || deploy_started_at
      logs = fetch_logs(kubectl, deploy_started_at: deploy_started_at, since: since, timestamps: true,
        unmanaged: unmanaged, container_names: container_names)

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

    def display_logs(kubectl, deploy_started_at, unmanaged, container_names)
      return if @already_displayed
      container_logs = fetch_logs(kubectl, deploy_started_at: deploy_started_at, unmanaged: unmanaged,
        container_names: container_names)

      if container_logs.empty?
        @logger.warn("No logs found for pod #{@pod_id}")
        return
      end

      container_logs.each do |container_identifier, logs|
        if logs.blank?
          @logger.warn("No logs found for container '#{container_identifier}'")
        else
          @logger.blank_line
          @logger.info("Logs from #{@pod_id} container '#{container_identifier}':")
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
