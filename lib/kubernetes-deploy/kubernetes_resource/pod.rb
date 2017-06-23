# frozen_string_literal: true
module KubernetesDeploy
  class Pod < KubernetesResource
    TIMEOUT = 10.minutes
    SUSPICIOUS_CONTAINER_STATES = %w(ImagePullBackOff RunContainerError ErrImagePull).freeze

    def initialize(namespace:, context:, definition:, logger:, parent: nil, deploy_started: nil)
      @parent = parent
      @deploy_started = deploy_started
      @containers = definition["spec"]["containers"].map { |c| c["name"] }
      super(namespace: namespace, context: context, definition: definition, logger: logger)
    end

    def sync(pod_data = nil)
      if pod_data.blank?
        raw_json, _err, st = kubectl.run("get", type, @name, "-a", "--output=json")
        pod_data = JSON.parse(raw_json) if st.success?
      end

      if pod_data.present?
        @found = true
        interpret_pod_status_data(pod_data["status"], pod_data["metadata"]) # sets @phase, @status and @ready
        if @deploy_started
          log_suspicious_states(pod_data["status"].fetch("containerStatuses", []))
        end
      else # reset
        @found = false
        @phase = @status = nil
        @ready = false
      end
      display_logs if unmanaged? && deploy_succeeded?
    end

    def deploy_succeeded?
      if unmanaged?
        @phase == "Succeeded"
      else
        @phase == "Running" && @ready
      end
    end

    def deploy_failed?
      @phase == "Failed"
    end

    def exists?
      @found
    end

    # Returns a hash in the following format:
    # {
    #   "pod/web-1/app-container" => "giant blob of logs\nas a single string"
    #   "pod/web-1/nginx-container" => "another giant blob of logs\nas a single string"
    # }
    def fetch_logs
      return {} unless exists? && @containers.present?

      @containers.each_with_object({}) do |container_name, container_logs|
        cmd = [
          "logs",
          @name,
          "--container=#{container_name}",
          "--since-time=#{@deploy_started.to_datetime.rfc3339}",
        ]
        cmd << "--tail=#{LOG_LINE_COUNT}" unless unmanaged?
        out, _err, _st = kubectl.run(*cmd)
        container_logs["#{id}/#{container_name}"] = out
      end
    end

    private

    def interpret_pod_status_data(status_data, metadata)
      @status = @phase = (metadata["deletionTimestamp"] ? "Terminating" : status_data["phase"])

      if @phase == "Failed" && status_data['reason'].present?
        @status += " (Reason: #{status_data['reason']})"
      elsif @phase != "Terminating"
        ready_condition = status_data.fetch("conditions", []).find { |condition| condition["type"] == "Ready" }
        @ready = ready_condition.present? && (ready_condition["status"] == "True")
        @status += " (Ready: #{@ready})"
      end
    end

    def log_suspicious_states(container_statuses)
      container_statuses.each do |status|
        waiting_state = status["state"]["waiting"] if status["state"]
        reason = waiting_state["reason"] if waiting_state
        next unless SUSPICIOUS_CONTAINER_STATES.include?(reason)
        @logger.warn("#{id} has container in state #{reason} (#{waiting_state['message']})")
      end
    end

    def unmanaged?
      @parent.blank?
    end

    def display_logs
      return if @already_displayed
      container_logs = fetch_logs

      if container_logs.empty?
        @logger.warn("No logs found for pod #{id}")
        return
      end

      container_logs.each do |container_identifier, logs|
        if logs.blank?
          @logger.warn("No logs found for #{container_identifier}")
        else
          @logger.blank_line
          @logger.info("Logs from #{container_identifier}:")
          logs.split("\n").each do |line|
            @logger.info("[#{container_identifier}]\t#{line}")
          end
          @logger.blank_line
        end
      end

      @already_displayed = true
    end
  end
end
