# frozen_string_literal: true
module KubernetesDeploy
  class Pod < KubernetesResource
    TIMEOUT = 10.minutes

    FAILED_PHASE_NAME = "Failed"
    TRANSIENT_FAILURE_REASONS = %w(
      Evicted
      Preempting
    )

    attr_accessor :stream_logs

    def initialize(namespace:, context:, definition:, logger:,
      statsd_tags: nil, parent: nil, deploy_started_at: nil, stream_logs: false)
      @parent = parent
      @deploy_started_at = deploy_started_at

      @containers = definition.fetch("spec", {}).fetch("containers", []).map { |c| Container.new(c) }
      unless @containers.present?
        logger.summary.add_paragraph("Rendered template content:\n#{definition.to_yaml}")
        raise FatalDeploymentError, "Template is missing required field spec.containers"
      end
      @containers += definition["spec"].fetch("initContainers", []).map { |c| Container.new(c, init_container: true) }
      @stream_logs = stream_logs
      super(namespace: namespace, context: context, definition: definition,
            logger: logger, statsd_tags: statsd_tags)
    end

    def sync(_cache)
      super
      raise_predates_deploy_error if exists? && unmanaged? && !deploy_started?

      if exists?
        logs.sync if unmanaged?
        update_container_statuses(@instance_data["status"])
      else # reset
        @containers.each(&:reset_status)
      end
    end

    def after_sync
      if @stream_logs
        logs.print_latest
      elsif unmanaged? && deploy_succeeded?
        logs.print_all
      end
    end

    def status
      return phase if reason.blank?
      "#{phase} (Reason: #{reason})"
    end

    def deploy_succeeded?
      if unmanaged?
        phase == "Succeeded"
      else
        phase == "Running" && ready?
      end
    end

    def deploy_failed?
      failure_message.present?
    end

    def timeout_message
      if readiness_probe_failure?
        probe_failure_msgs = @containers.map(&:readiness_fail_reason).compact
        header = "The following containers have not passed their readiness probes on at least one pod:\n"
        header + probe_failure_msgs.join("\n")
      elsif failed_schedule_reason.present?
        "Pod could not be scheduled because #{failed_schedule_reason}"
      else
        STANDARD_TIMEOUT_MESSAGE
      end
    end

    def failure_message
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
      "#{phase_failure_message} #{container_problems}".strip.presence
    end

    def fetch_debug_logs
      logs.sync
      logs
    end

    def print_debug_logs?
      exists? && !@stream_logs # don't print them a second time
    end

    private

    def failed_schedule_reason
      if phase == "Pending"
        conditions = @instance_data.dig('status', 'conditions') || []
        unschedulable = conditions.find do |condition|
          condition["type"] == "PodScheduled" && condition["status"] == "False"
        end
        unschedulable&.dig('message')
      end
    end

    def failed_phase?
      phase == FAILED_PHASE_NAME
    end

    def transient_failure_reason?
      return false if unmanaged?
      TRANSIENT_FAILURE_REASONS.include?(reason)
    end

    def phase_failure_message
      if failed_phase? && !transient_failure_reason?
        return "Pod status: #{status}."
      end

      return unless unmanaged?

      if terminating?
        "Pod status: Terminating."
      elsif disappeared?
        "Pod status: Disappeared."
      end
    end

    def logs
      @logs ||= KubernetesDeploy::RemoteLogs.new(
        logger: @logger,
        parent_id: id,
        container_names: @containers.map(&:name),
        namespace: @namespace,
        context: @context
      )
    end

    def phase
      @instance_data.dig("status", "phase") || "Unknown"
    end

    def reason
      @instance_data.dig('status', 'reason')
    end

    def readiness_probe_failure?
      return false if ready? || unmanaged?
      return false if phase != "Running"
      @containers.any?(&:readiness_fail_reason)
    end

    def ready?
      return false unless (status_data = @instance_data["status"])
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
        elsif limbo_reason == "ErrImagePull" && limbo_message.match(/not found/i)
          "Failed to pull image #{@image}. "\
          "Did you wait for it to be built and pushed to the registry before deploying?"
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
