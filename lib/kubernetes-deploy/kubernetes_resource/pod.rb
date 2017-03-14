# frozen_string_literal: true
module KubernetesDeploy
  class Pod < KubernetesResource
    TIMEOUT = 10.minutes
    SUSPICIOUS_CONTAINER_STATES = %w(ImagePullBackOff RunContainerError).freeze

    def initialize(name, namespace, context, file, parent: nil)
      @name = name
      @namespace = namespace
      @context = context
      @file = file
      @parent = parent
      @bare = !@parent
    end

    def sync
      out, st = run_kubectl("get", type, @name, "-a", "--output=json")
      if @found = st.success?
        pod_data = JSON.parse(out)
        interpret_json_data(pod_data)
      else # reset
        @status = @phase = nil
        @ready = false
        @containers = []
      end
      display_logs if @bare && deploy_finished?
      log_status
    end

    def interpret_json_data(pod_data)
      @phase = (pod_data["metadata"]["deletionTimestamp"] ? "Terminating" : pod_data["status"]["phase"])
      @containers = pod_data["spec"]["containers"].map { |c| c["name"] }

      if @deploy_started && pod_data["status"]["containerStatuses"]
        pod_data["status"]["containerStatuses"].each do |status|
          waiting_state = status["state"]["waiting"] if status["state"]
          reason = waiting_state["reason"] if waiting_state
          next unless SUSPICIOUS_CONTAINER_STATES.include?(reason)
          KubernetesDeploy.logger.warn("#{id} has container in state #{reason} (#{waiting_state['message']})")
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
      if @bare
        @phase == "Succeeded"
      else
        @phase == "Running" && @ready
      end
    end

    def deploy_failed?
      @phase == "Failed"
    end

    def exists?
      @bare ? @found : true
    end

    def group_name
      @bare ? "Bare pods" : @parent
    end

    private

    def display_logs
      return {} unless exists? && @containers.present? && !@already_displayed

      @containers.each do |container_name|
        out, st = run_kubectl("logs", @name, "--timestamps=true", "--since-time=#{@deploy_started.to_datetime.rfc3339}")
        next unless st.success? && out.present?

        KubernetesDeploy.logger.info "Logs from #{id} container #{container_name}:"
        KubernetesResource.logger.info(out)
        @already_displayed = true
      end
    end
  end
end
