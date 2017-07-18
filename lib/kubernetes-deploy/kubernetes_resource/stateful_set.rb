# frozen_string_literal: true
require 'kubernetes-deploy/kubernetes_resource/pod_set_base'
module KubernetesDeploy
  class StatefulSet < PodSetBase
    TIMEOUT = 10.minutes
    ONDELETE = 'OnDelete'
    attr_reader :pods

    def sync
      raw_json, _err, st = kubectl.run("get", type, @name, "--output=json")
      @found = st.success?

      if @found
        stateful_data = JSON.parse(raw_json)
        @desired_replicas = stateful_data["spec"]["replicas"].to_i
        @status_data = stateful_data["status"]
        rollout_data = stateful_data["status"].slice("replicas", "readyReplicas", "currentReplicas")
        @update_strategy = if kubectl.server_version < Gem::Version.new("1.7.0")
          ONDELETE
        else
          stateful_data['spec']['updateStrategy']['type']
        end
        @status = rollout_data.map { |state_replicas, num| "#{num} #{state_replicas.chop.pluralize(num)}" }.join(", ")
        @pods = find_pods(stateful_data)
      else # reset
        @status_data = { 'readyReplicas' => '-1', 'currentReplicas' => '-2' }
        @status = nil
        @pods = []
      end
    end

    def deploy_succeeded?
      if @update_strategy == ONDELETE
        # Gem cannot monitor update since it doesn't occur until delete
        unless @success_assumption_warning_shown
          @logger.warn("WARNING: Your StatefulSet's updateStrategy is set to OnDelete, "\
                       "which means updates will not be applied until its pods are deleted. "\
                       "If you are using k8s 1.7+, consider switching to rollingUpdate.")
          @success_assumption_warning_shown = true
        end
        true
      else
        @status_data['currentRevision'] == @status_data['updateRevision'] &&
        @desired_replicas == @status_data['readyReplicas'].to_i &&
        @desired_replicas == @status_data['currentReplicas'].to_i
      end
    end

    def deploy_failed?
      return false if @update_strategy == ONDELETE
      pods.present? && pods.any?(&:deploy_failed?)
    end

    def exists?
      @found
    end

    private

    def parent_of_pod?(set_data, pod_data)
      return false unless pod_data.dig("metadata", "ownerReferences")
      pod_data["metadata"]["ownerReferences"].any? { |ref| ref["uid"] == set_data["metadata"]["uid"] } &&
      set_data["status"]["currentRevision"] == pod_data["metadata"]["labels"]["controller-revision-hash"]
    end
  end
end
