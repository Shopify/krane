# frozen_string_literal: true
module KubernetesDeploy
  class Pod < KubernetesResource
    TIMEOUT = 10.minutes
    SUSPICIOUS_CONTAINER_STATES = %w(ImagePullBackOff RunContainerError ErrImagePull).freeze

    def initialize(name:, namespace:, context:, file:, parent: nil, logger:)
      @name = name
      @namespace = namespace
      @context = context
      @file = file
      @parent = parent
      @logger = logger
    end

    def sync
      out, _err, st = kubectl.run("get", type, @name, "-a", "--output=json")
      if @found = st.success?
        pod_data = JSON.parse(out)
        interpret_json_data(pod_data)
      else # reset
        @status = @phase = nil
        @ready = false
        @containers = []
      end
      display_logs if unmanaged? && deploy_succeeded?
    end

    def interpret_json_data(pod_data)
      @phase = (pod_data["metadata"]["deletionTimestamp"] ? "Terminating" : pod_data["status"]["phase"])
      @containers = pod_data["spec"]["containers"].map { |c| c["name"] }

      if @deploy_started && pod_data["status"]["containerStatuses"]
        pod_data["status"]["containerStatuses"].each do |status|
          waiting_state = status["state"]["waiting"] if status["state"]
          reason = waiting_state["reason"] if waiting_state
          next unless SUSPICIOUS_CONTAINER_STATES.include?(reason)
          @logger.warn("#{id} has container in state #{reason} (#{waiting_state['message']})")
        end
      end

      if @phase == "Failed"
        @status = "#{@phase} (Reason: #{pod_data['status']['reason']})"
      elsif @phase == "Terminating"
        @status = @phase
      else
        ready_condition = pod_data["status"].fetch("conditions", []).find { |condition| condition["type"] == "Ready" }
        @ready = ready_condition.present? && (ready_condition["status"] == "True")
        @status = "#{@phase} (Ready: #{@ready})"
      end
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
      unmanaged? ? @found : true
    end

    # Returns a hash in the following format:
    # {
    #   "pod/web-1/app-container" => "giant blob of logs\nas a single string"
    #   "pod/web-1/nginx-container" => "another giant blob of logs\nas a single string"
    # }
    def fetch_logs
      return {} unless exists? && @containers.present?

      @containers.each_with_object({}) do |container_name, container_logs|
        out, _err, _st = kubectl.run(
          "logs",
          @name,
          "--timestamps=true",
          "--container=#{container_name}",
          "--since-time=#{@deploy_started.to_datetime.rfc3339}"
        )
        container_logs["#{id}/#{container_name}"] = out
      end
    end

    private

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
