# frozen_string_literal: true
require 'kubernetes-deploy/kubernetes_resource/pod'

module KubernetesDeploy
  class PodSetBase < KubernetesResource
    def failure_message
      pods.map(&:failure_message).compact.uniq.join("\n")
    end

    def timeout_message
      pods.map(&:timeout_message).compact.uniq.join("\n")
    end

    def fetch_events(kubectl)
      own_events = super
      return own_events unless pods.present?
      most_useful_pod = pods.find(&:deploy_failed?) || pods.find(&:deploy_timed_out?) || pods.first
      own_events.merge(most_useful_pod.fetch_events(kubectl))
    end

    def fetch_debug_logs
      logs = KubernetesDeploy::RemoteLogs.new(
        logger: @logger,
        parent_id: id,
        container_names: container_names,
        namespace: @namespace,
        context: @context
      )
      logs.sync
      logs
    end

    def print_debug_logs?
      pods.present? # the kubectl command times out if no pods exist
    end

    private

    def pods
      raise NotImplementedError, "Subclasses must define a `pods` accessor"
    end

    def parent_of_pod?(_)
      raise NotImplementedError, "Subclasses must define a `parent_of_pod?` method"
    end

    def container_names
      regular_containers = @definition["spec"]["template"]["spec"]["containers"].map { |c| c["name"] }
      init_containers = @definition["spec"]["template"]["spec"].fetch("initContainers", {}).map { |c| c["name"] }
      regular_containers + init_containers
    end

    def find_pods(cache)
      all_pods = cache.get_all(Pod.kind, @instance_data["spec"]["selector"]["matchLabels"])

      all_pods.each_with_object([]) do |pod_data, relevant_pods|
        next unless parent_of_pod?(pod_data)
        pod = Pod.new(
          namespace: namespace,
          context: context,
          definition: pod_data,
          logger: @logger,
          parent: "#{name.capitalize} #{type}",
          deploy_started_at: @deploy_started_at
        )
        pod.sync(cache)
        relevant_pods << pod
      end
    end
  end
end
