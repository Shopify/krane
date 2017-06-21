# frozen_string_literal: true
module KubernetesDeploy
  class Deployment < KubernetesResource
    TIMEOUT = 5.minutes

    def sync
      json_data, _err, st = kubectl.run("get", type, @name, "--output=json")
      @found = st.success?
      @rollout_data = {}
      @status = nil
      @representative_pod = nil
      @pods = []

      if @found
        @rollout_data = JSON.parse(json_data)["status"]
          .slice("updatedReplicas", "replicas", "availableReplicas", "unavailableReplicas")
        @status = @rollout_data.map { |replica_state, num| "#{num} #{replica_state}" }.join(", ")

        pod_list, _err, st = kubectl.run("get", "pods", "-a", "-l", "name=#{name}", "--output=json")
        if st.success?
          pods_json = JSON.parse(pod_list)["items"]
          pods_json.each do |pod_json|
            pod = Pod.new(
              namespace: namespace,
              context: context,
              template: pod_json,
              logger: @logger,
              parent: "#{@name.capitalize} deployment",
              deploy_started: @deploy_started
            )
            pod.sync(pod_json)

            if !@representative_pod && pod_probably_new?(pod_json)
              @representative_pod = pod
            end
            @pods << pod
          end
        end
      end
    end

    def fetch_logs
      @representative_pod ? @representative_pod.fetch_logs : {}
    end

    def fetch_events
      own_events = super
      return own_events unless @representative_pod
      own_events.merge(@representative_pod.fetch_events)
    end

    def deploy_succeeded?
      return false unless @rollout_data.key?("availableReplicas")
      # TODO: this should look at the current replica set's pods too
      @rollout_data["updatedReplicas"].to_i == @rollout_data["replicas"].to_i &&
      @rollout_data["updatedReplicas"].to_i == @rollout_data["availableReplicas"].to_i
    end

    def deploy_failed?
      # TODO: this should look at the current replica set's pods only or it'll never be true for rolling updates
      @pods.present? && @pods.all?(&:deploy_failed?)
    end

    def deploy_timed_out?
      # TODO: this should look at the current replica set's pods only or it'll never be true for rolling updates
      super || @pods.present? && @pods.all?(&:deploy_timed_out?)
    end

    def exists?
      @found
    end

    private

    def pod_probably_new?(pod_json)
      return false unless @deploy_started
      # Shitty, brittle workaround to identify a pod from the new ReplicaSet before implementing ReplicaSet awareness
      Time.parse(pod_json["metadata"]["creationTimestamp"]) >= (@deploy_started - 30.seconds)
    end
  end
end
