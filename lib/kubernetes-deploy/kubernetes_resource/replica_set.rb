# frozen_string_literal: true
module KubernetesDeploy
  class ReplicaSet < KubernetesResource
    TIMEOUT = 5.minutes
    attr_reader :desired_replicas

    def initialize(namespace:, context:, definition:, logger:, parent: nil, deploy_started: nil)
      @parent = parent
      @deploy_started = deploy_started
      @rollout_data = { "replicas" => 0 }
      @pods = []
      super(namespace: namespace, context: context, definition: definition, logger: logger)
    end

    def sync(rs_data = nil)
      if rs_data.blank?
        raw_json, _err, st = kubectl.run("get", type, @name, "--output=json")
        rs_data = JSON.parse(raw_json) if st.success?
      end

      if rs_data.present?
        @found = true
        @desired_replicas = rs_data["spec"]["replicas"].to_i
        @rollout_data = { "replicas" => 0 }.merge(rs_data["status"]
          .slice("replicas", "availableReplicas", "readyReplicas"))
        @status = @rollout_data.map { |state_replicas, num| "#{num} #{state_replicas.chop.pluralize(num)}" }.join(", ")
        @pods = find_pods(rs_data)
      else # reset
        @found = false
        @rollout_data = { "replicas" => 0 }
        @status = nil
        @pods = []
      end
    end

    def deploy_succeeded?
      @desired_replicas == @rollout_data["availableReplicas"].to_i &&
      @desired_replicas == @rollout_data["readyReplicas"].to_i
    end

    def deploy_failed?
      @pods.present? && @pods.all?(&:deploy_failed?)
    end

    def failure_message
      @pods.map(&:failure_message).compact.uniq.join("\n")
    end

    def timeout_message
      @pods.map(&:timeout_message).compact.uniq.join("\n")
    end

    def deploy_timed_out?
      super || @pods.present? && @pods.all?(&:deploy_timed_out?)
    end

    def exists?
      @found
    end

    def fetch_events
      own_events = super
      return own_events unless @pods.present?
      most_useful_pod = @pods.find(&:deploy_failed?) || @pods.find(&:deploy_timed_out?) || @pods.first
      own_events.merge(most_useful_pod.fetch_events)
    end

    def fetch_logs
      container_names.each_with_object({}) do |container_name, container_logs|
        out, _err, _st = kubectl.run(
          "logs",
          id,
          "--container=#{container_name}",
          "--since-time=#{@deploy_started.to_datetime.rfc3339}",
          "--tail=#{LOG_LINE_COUNT}"
        )
        container_logs[container_name] = out.split("\n")
      end
    end

    private

    def unmanaged?
      @parent.blank?
    end

    def container_names
      regular_containers = @definition["spec"]["template"]["spec"]["containers"].map { |c| c["name"] }
      init_containers = @definition["spec"]["template"]["spec"].fetch("initContainers", {}).map { |c| c["name"] }
      regular_containers + init_containers
    end

    def find_pods(rs_data)
      label_string = rs_data["spec"]["selector"]["matchLabels"].map { |k, v| "#{k}=#{v}" }.join(",")
      raw_json, _err, st = kubectl.run("get", "pods", "-a", "--output=json", "--selector=#{label_string}")
      return [] unless st.success?

      all_pods = JSON.parse(raw_json)["items"]
      all_pods.each_with_object([]) do |pod_data, relevant_pods|
        next unless pod_data["metadata"]["ownerReferences"].any? { |ref| ref["uid"] == rs_data["metadata"]["uid"] }
        pod = Pod.new(
          namespace: namespace,
          context: context,
          definition: pod_data,
          logger: @logger,
          parent: "#{@name.capitalize} replica set",
          deploy_started: @deploy_started
        )
        pod.sync(pod_data)
        relevant_pods << pod
      end
    end
  end
end
