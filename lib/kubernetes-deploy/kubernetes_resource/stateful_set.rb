# frozen_string_literal: true
require 'kubernetes-deploy/kubernetes_resource/pod_set_base'
module KubernetesDeploy
  class StatefulSet < PodSetBase
    TIMEOUT = 10.minutes
    ONDELETE = 'OnDelete'
    attr_reader :pods

    def sync(mediator)
      super
      @pods = exists? ? find_pods(mediator) : []
      @server_version = mediator.kubectl.server_version
    end

    def status
      return super unless @instance_data["status"].present?
      rollout_data = @instance_data["status"].slice("replicas", "readyReplicas", "currentReplicas")
      rollout_data.map { |state_replicas, num| "#{num} #{state_replicas.chop.pluralize(num)}" }.join(", ")
    end

    def deploy_succeeded?
      if update_strategy == ONDELETE
        # Gem cannot monitor update since it doesn't occur until delete
        unless @success_assumption_warning_shown
          @logger.warn("WARNING: Your StatefulSet's updateStrategy is set to OnDelete, "\
                       "which means updates will not be applied until its pods are deleted. "\
                       "If you are using k8s 1.7+, consider switching to rollingUpdate.")
          @success_assumption_warning_shown = true
        end
        true
      else
        status_data['currentRevision'] == status_data['updateRevision'] &&
        desired_replicas == status_data['readyReplicas'].to_i &&
        desired_replicas == status_data['currentReplicas'].to_i
      end
    end

    def deploy_failed?
      return false if update_strategy == ONDELETE
      pods.present? && pods.any?(&:deploy_failed?)
    end

    private

    def update_strategy
      if @server_version < Gem::Version.new("1.7.0")
        ONDELETE
      elsif exists?
        @instance_data['spec']['updateStrategy']['type']
      else
        'Unknown'
      end
    end

    def status_data
      return { 'readyReplicas' => '-1', 'currentReplicas' => '-2' } unless exists?
      @instance_data["status"]
    end

    def desired_replicas
      return -1 unless exists?
      @instance_data["spec"]["replicas"].to_i
    end

    def parent_of_pod?(pod_data)
      return false unless pod_data.dig("metadata", "ownerReferences")
      pod_data["metadata"]["ownerReferences"].any? { |ref| ref["uid"] == @instance_data["metadata"]["uid"] } &&
      @instance_data["status"]["currentRevision"] == pod_data["metadata"]["labels"]["controller-revision-hash"]
    end
  end
end
