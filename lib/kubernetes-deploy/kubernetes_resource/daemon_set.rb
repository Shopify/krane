# frozen_string_literal: true
module KubernetesDeploy
  class DaemonSet < KubernetesResource
    TIMEOUT = 5.minutes

    def sync
      raw_json, _err, st = kubectl.run("get", type, @name, "--output=json")
      @found = st.success?

      if @found
        daemonset_data = JSON.parse(raw_json)
        @current_generation = daemonset_data["metadata"]["generation"]
        @observed_generation = daemonset_data["status"]["observedGeneration"]
        @rollout_data = daemonset_data["status"]
          .slice("currentNumberScheduled", "desiredNumberScheduled", "numberReady")
        @status = @rollout_data.map { |state_replicas, num| "#{num} #{state_replicas}" }.join(", ")
        @pods = find_pods(daemonset_data)
      else # reset
        @rollout_data = { "currentNumberScheduled" => 0 }
        @current_generation = 1 # to make sure the current and observed generations are different
        @observed_generation = 0
        @status = nil
        @pods = []
      end
    end

    def deploy_succeeded?
      @rollout_data["desiredNumberScheduled"].to_i == @rollout_data["currentNumberScheduled"].to_i &&
      @rollout_data["desiredNumberScheduled"].to_i == @rollout_data["numberReady"].to_i &&
      @current_generation == @observed_generation
    end

    def deploy_failed?
      @pods.present? && @pods.any?(&:deploy_failed?)
    end

    def failure_message
      @pods.map(&:failure_message).compact.uniq.join("\n")
    end

    def timeout_message
      STANDARD_TIMEOUT_MESSAGE unless @pods.present?
      @pods.map(&:timeout_message).compact.uniq.join("\n")
    end

    def deploy_timed_out?
      super || @pods.present? && @pods.any?(&:deploy_timed_out?)
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
      most_useful_pod = @pods.find(&:deploy_failed?) || @pods.find(&:deploy_timed_out?) || @pods.first
      most_useful_pod.fetch_logs
    end

    private

    def find_pods(ds_data)
      label_string = ds_data["spec"]["selector"]["matchLabels"].map { |k, v| "#{k}=#{v}" }.join(",")
      raw_json, _err, st = kubectl.run("get", "pods", "-a", "--output=json", "--selector=#{label_string}")
      return [] unless st.success?

      all_pods = JSON.parse(raw_json)["items"]
      current_generation = ds_data["metadata"]["generation"]

      latest_pods = all_pods.find_all do |pods|
        pods["metadata"]["ownerReferences"].any? { |ref| ref["uid"] == ds_data["metadata"]["uid"] } &&
        pods["metadata"]["labels"]["pod-template-generation"].to_i == current_generation.to_i
      end
      return unless latest_pods.present?

      latest_pods.each_with_object([]) do |pod_data, relevant_pods|
        pod = Pod.new(
          namespace: namespace,
          context: context,
          definition: pod_data,
          logger: @logger,
          parent: "#{@name.capitalize} daemon set",
          deploy_started: @deploy_started
        )
        pod.sync(pod_data)
        relevant_pods << pod
      end
    end
  end
end
