# frozen_string_literal: true
module KubernetesDeploy
  class Deployment < KubernetesResource
    TIMEOUT = 5.minutes

    def sync
      json_data, _err, st = kubectl.run("get", type, @name, "--output=json")
      @found = st.success?
      @rollout_data = {}
      @status = nil
      @pods = []

      if @found
        @rollout_data = JSON.parse(json_data)["status"]
          .slice("updatedReplicas", "replicas", "availableReplicas", "unavailableReplicas")
        @status, _err, _ = kubectl.run("rollout", "status", type, @name, "--watch=false") if @deploy_started

        pod_list, _err, st = kubectl.run("get", "pods", "-a", "-l", "name=#{name}", "--output=json")
        if st.success?
          pods_json = JSON.parse(pod_list)["items"]
          pods_json.each do |pod_json|
            pod_name = pod_json["metadata"]["name"]
            pod = Pod.new(
              name: pod_name,
              namespace: namespace,
              context: context,
              file: nil,
              parent: "#{@name.capitalize} deployment",
              logger: @logger
            )
            pod.deploy_started = @deploy_started
            pod.interpret_json_data(pod_json)
            @pods << pod
          end
        end
      end

      log_status
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

    def status_data
      super.merge(replicas: @rollout_data, num_pods: @pods.length)
    end
  end
end
