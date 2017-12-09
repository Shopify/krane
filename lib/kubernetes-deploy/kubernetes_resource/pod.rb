# frozen_string_literal: true
module KubernetesDeploy
  class Pod < KubernetesResource
    TIMEOUT = 10.minutes

    FAILED_PHASE_NAME = "Failed"

    def initialize(namespace:, context:, definition:, logger:, parent: nil, deploy_started_at: nil)
      @parent = parent
      @deploy_started_at = deploy_started_at
      @containers = definition.fetch("spec", {}).fetch("containers", []).map { |c| Container.new(c) }
      unless @containers.present?
        logger.summary.add_paragraph("Rendered template content:\n#{definition.to_yaml}")
        raise FatalDeploymentError, "Template is missing required field spec.containers"
      end
      @containers += definition["spec"].fetch("initContainers", []).map { |c| Container.new(c, init_container: true) }
      super(namespace: namespace, context: context, definition: definition, logger: logger)
    end

    def sync(pod_data = nil)
      if pod_data.blank?
        raw_json, _err, st = kubectl.run("get", type, @name, "-a", "--output=json")
        pod_data = JSON.parse(raw_json) if st.success?
        raise_predates_deploy_error if pod_data.present? && unmanaged? && !deploy_started?
      end

      if pod_data.present?
        @found = true
        @phase = @status = pod_data["status"]["phase"]
        @status += " (Reason: #{pod_data['status']['reason']})" if pod_data['status']['reason'].present?
        @ready = ready?(pod_data["status"])
        update_container_statuses(pod_data["status"])
      else # reset
        @found = @ready = false
        @status = @phase = 'Unknown'
        @containers.each(&:reset_status)
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
      failure_message.present?
    end

    def exists?
      @found
    end

    def timeout_message
      return STANDARD_TIMEOUT_MESSAGE unless readiness_probe_failure?
      probe_failure_msgs = @containers.map(&:readiness_fail_reason).compact
      header = "The following containers have not passed their readiness probes on at least one pod:\n"
      header + probe_failure_msgs.join("\n") + "\n"
    end

    def failure_message
      if @phase == FAILED_PHASE_NAME
        phase_problem = "Pod status: #{@status}. "
      end

      doomed_containers = @containers.select(&:doomed?)
      if doomed_containers.present?
        container_problems = if unmanaged?
          "The following containers encountered errors:\n"
        else
          "The following containers are in a state that is unlikely to be recoverable:\n"
        end
        doomed_containers.each do |c|
          red_name = ColorizedString.new(c.name).red
          container_problems += "> #{red_name}: #{c.doom_reason}\n"
        end
      end
      "#{phase_problem}#{container_problems}".presence
    end

    # Returns a hash in the following format:
    # {
    #   "app" => ["array of log lines", "received from app container"],
    #   "nginx" => ["array of log lines", "received from nginx container"]
    # }
    def fetch_logs
      return {} unless exists? && @containers.present?
      @containers.each_with_object({}) do |container, container_logs|
        cmd = [
          "logs",
          @name,
          "--container=#{container.name}",
          "--since-time=#{@deploy_started_at.to_datetime.rfc3339}",
        ]
        cmd << "--tail=#{LOG_LINE_COUNT}" unless unmanaged?
        out, _err, _st = kubectl.run(*cmd)
        container_logs[container.name] = out.split("\n")
      end
    end

    private

    def readiness_probe_failure?
      return false if @ready || unmanaged?
      return false if @phase != "Running"
      @containers.any?(&:readiness_fail_reason)
    end

    def ready?(status_data)
      ready_condition = status_data.fetch("conditions", []).find { |condition| condition["type"] == "Ready" }
      ready_condition.present? && (ready_condition["status"] == "True")
    end

    def update_container_statuses(status_data)
      @containers.each do |c|
        key = c.init_container? ? "initContainerStatuses" : "containerStatuses"
        if status_data.key?(key)
          data = status_data[key].find { |st| st["name"] == c.name }
          c.update_status(data)
        else
          c.reset_status
        end
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
          @logger.warn("No logs found for container '#{container_identifier}'")
        else
          @logger.blank_line
          @logger.info("Logs from #{id} container '#{container_identifier}':")
          logs.each { |line| @logger.info("\t#{line}") }
          @logger.blank_line
        end
      end

      @already_displayed = true
    end

    def raise_predates_deploy_error
      example_color = :green
      msg = <<-STRING.strip_heredoc
        Unmanaged pods like #{id} must have unique names on every deploy in order to work as intended.
        The recommended way to achieve this is to include "<%= deployment_id %>" in the pod's name, like this:
          #{ColorizedString.new('kind: Pod').colorize(example_color)}
          #{ColorizedString.new('metadata:').colorize(example_color)}
            #{ColorizedString.new("name: #{@name}-<%= deployment_id %>").colorize(example_color)}
      STRING
      @logger.summary.add_paragraph(msg)
      raise FatalDeploymentError, "#{id} existed before the deploy started"
    end

    class Container
      attr_reader :name

      def initialize(definition, init_container: false)
        @init_container = init_container
        @name = definition["name"]
        @image = definition["image"]
        @http_probe_location = definition.dig("readinessProbe", "httpGet", "path")
        @exec_probe_command = definition.dig("readinessProbe", "exec", "command")
        @status = {}
      end

      def doomed?
        doom_reason.present?
      end

      def doom_reason
        limbo_reason = @status.dig("state", "waiting", "reason")
        limbo_message = @status.dig("state", "waiting", "message")

        if @status.dig("lastState", "terminated", "reason") == "ContainerCannotRun"
          # ref: https://github.com/kubernetes/kubernetes/blob/562e721ece8a16e05c7e7d6bdd6334c910733ab2/pkg/kubelet/dockershim/docker_container.go#L353
          exit_code = @status.dig('lastState', 'terminated', 'exitCode')
          "Failed to start (exit #{exit_code}): #{@status.dig('lastState', 'terminated', 'message')}"
        elsif @status.dig("state", "terminated", "reason") == "ContainerCannotRun"
          exit_code = @status.dig('state', 'terminated', 'exitCode')
          "Failed to start (exit #{exit_code}): #{@status.dig('state', 'terminated', 'message')}"
        elsif limbo_reason == "CrashLoopBackOff"
          exit_code = @status.dig('lastState', 'terminated', 'exitCode')
          "Crashing repeatedly (exit #{exit_code}). See logs for more information."
        elsif %w(ImagePullBackOff ErrImagePull).include?(limbo_reason) &&
          limbo_message.match(/(?:not found)|(?:back-off)/i)
          "Failed to pull image #{@image}. "\
          "Did you wait for it to be built and pushed to the registry before deploying?"
        elsif limbo_message == "Generate Container Config Failed"
          # reason/message are backwards in <1.8.0 (next condition used by 1.8.0+)
          # Fixed by https://github.com/kubernetes/kubernetes/commit/df41787b1a3f51b73fb6db8a2203f0a7c7c92931
          "Failed to generate container configuration: #{limbo_reason}"
        elsif limbo_reason == "CreateContainerConfigError"
          "Failed to generate container configuration: #{limbo_message}"
        end
      end

      def readiness_fail_reason
        return if ready? || init_container?
        return unless (@http_probe_location || @exec_probe_command).present?

        yellow_name = ColorizedString.new(name).yellow
        if @http_probe_location
          "> #{yellow_name} must respond with a good status code at '#{@http_probe_location}'"
        elsif @exec_probe_command
          "> #{yellow_name} must exit 0 from the following command: '#{@exec_probe_command.join(' ')}'"
        end
      end

      def ready?
        @status['ready'] == true
      end

      def init_container?
        @init_container
      end

      def update_status(data)
        @status = data || {}
      end

      def reset_status
        @status = {}
      end
    end
  end
end
