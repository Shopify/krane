# frozen_string_literal: true
module KubernetesDeploy
  class Pod < KubernetesResource
    TIMEOUT = 10.minutes

    def initialize(namespace:, context:, definition:, logger:, parent: nil, deploy_started: nil)
      @parent = parent
      @deploy_started = deploy_started
      @containers = definition.fetch("spec", {}).fetch("containers", []).map { |c| Container.new(c) }
      unless @containers.present?
        logger.summary.add_paragraph("Rendered template content:\n#{definition.to_yaml}")
        raise FatalDeploymentError, "Template is missing required field spec.containers"
      end
      @containers += definition["spec"].fetch("initContainers", []).map { |c| Container.new(c, init: true) }
      super(namespace: namespace, context: context, definition: definition, logger: logger)
    end

    def sync(pod_data = nil)
      if pod_data.blank?
        raw_json, _err, st = kubectl.run("get", type, @name, "-a", "--output=json")
        pod_data = JSON.parse(raw_json) if st.success?
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
      return true if @phase == "Failed"
      @containers.any?(&:doomed?)
    end

    def exists?
      @found
    end

    def timeout_message
      return unless @phase == "Running" && !@ready
      pieces = ["Your pods are running, but the following containers seem to be failing their readiness probes:"]
      @containers.each do |c|
        next if c.init_container? || c.ready?
        yellow_name = ColorizedString.new(c.name).yellow
        pieces << "> #{yellow_name} must respond with a good status code at '#{c.probe_location}'"
      end
      pieces.join("\n") + "\n"
    end

    def failure_message
      doomed_containers = @containers.select(&:doomed?)
      return unless doomed_containers.present?
      container_messages = doomed_containers.map do |c|
        red_name = ColorizedString.new(c.name).red
        "> #{red_name}: #{c.doom_reason}"
      end
      intro = "The following containers are in a state that is unlikely to be recoverable:\n"
      intro + container_messages.join("\n") + "\n"
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
          "--since-time=#{@deploy_started.to_datetime.rfc3339}",
        ]
        cmd << "--tail=#{LOG_LINE_COUNT}" unless unmanaged?
        out, _err, _st = kubectl.run(*cmd)
        container_logs[container.name] = out.split("\n")
      end
    end

    private

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

    class Container
      STATUS_SCAFFOLD = {
        "state" => {
          "running" => {},
          "waiting" => {},
          "terminated" => {},
        },
        "lastState" => {
          "terminated" => {}
        }
      }.freeze

      attr_reader :name, :probe_location

      def initialize(definition, init: false)
        @init = init
        @name = definition["name"]
        @image = definition["image"]
        @probe_location = definition.fetch("readinessProbe", {}).fetch("httpGet", {})["path"]
        @status = STATUS_SCAFFOLD.dup
      end

      def doomed?
        doom_reason.present?
      end

      def doom_reason
        exit_code = @status['lastState']['terminated']['exitCode']
        last_terminated_reason = @status["lastState"]["terminated"]["reason"]
        limbo_reason = @status["state"]["waiting"]["reason"]

        if last_terminated_reason == "ContainerCannotRun"
          # ref: https://github.com/kubernetes/kubernetes/blob/562e721ece8a16e05c7e7d6bdd6334c910733ab2/pkg/kubelet/dockershim/docker_container.go#L353
          "Failing to start (exit #{exit_code}): #{@status['lastState']['terminated']['message']}"
        elsif limbo_reason == "CrashLoopBackOff"
          "Crashing repeatedly (exit #{exit_code}). See logs for more information."
        elsif %w(ImagePullBackOff ErrImagePull).include?(limbo_reason)
          "Failing to pull image #{@image}. "\
          "Did you wait for it to be built and pushed to the registry before deploying?"
        elsif @status["state"]["waiting"]["message"] == "Generate Container Config Failed"
          # reason/message seem to be backwards for this case -- reason is the free-form part
          "Failing to generate container configuration: #{limbo_reason}"
        end
      end

      def ready?
        @status['ready'] == "true"
      end

      def init_container?
        @init
      end

      def update_status(data)
        @status = STATUS_SCAFFOLD.deep_merge(data || {})
      end

      def reset_status
        @status = STATUS_SCAFFOLD.dup
      end
    end
  end
end
