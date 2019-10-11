# frozen_string_literal: true
require 'kubernetes-deploy/kubernetes_resource/replica_set'

module KubernetesDeploy
  class Deployment < KubernetesResource
    TIMEOUT = 7.minutes
    REQUIRED_ROLLOUT_ANNOTATION_SUFFIX = "required-rollout"
    REQUIRED_ROLLOUT_ANNOTATION_DEPRECATED = "kubernetes-deploy.shopify.io/#{REQUIRED_ROLLOUT_ANNOTATION_SUFFIX}"
    REQUIRED_ROLLOUT_ANNOTATION = "krane.shopify.io/#{REQUIRED_ROLLOUT_ANNOTATION_SUFFIX}"
    REQUIRED_ROLLOUT_TYPES = %w(maxUnavailable full none).freeze
    DEFAULT_REQUIRED_ROLLOUT = 'full'

    def sync(cache)
      super
      @latest_rs = exists? ? find_latest_rs(cache) : nil
    end

    def status
      return super unless exists?
      rollout_data.map { |state_replicas, num| "#{num} #{state_replicas.chop.pluralize(num)}" }.join(", ")
    end

    def fetch_events(kubectl)
      own_events = super
      return own_events unless @latest_rs.present?
      own_events.merge(@latest_rs.fetch_events(kubectl))
    end

    def print_debug_logs?
      @latest_rs.present?
    end

    def fetch_debug_logs
      @latest_rs.fetch_debug_logs
    end

    def deploy_succeeded?
      return false unless exists? && @latest_rs.present?
      return false unless observed_generation == current_generation

      if required_rollout == 'full'
        @latest_rs.deploy_succeeded? &&
        @latest_rs.desired_replicas == desired_replicas && # latest RS fully scaled up
        rollout_data["updatedReplicas"].to_i == desired_replicas &&
        rollout_data["updatedReplicas"].to_i == rollout_data["availableReplicas"].to_i
      elsif required_rollout == 'none'
        true
      elsif required_rollout == 'maxUnavailable' || percent?(required_rollout)
        minimum_needed = min_available_replicas

        @latest_rs.desired_replicas >= minimum_needed &&
        @latest_rs.ready_replicas >= minimum_needed &&
        @latest_rs.available_replicas >= minimum_needed
      else
        raise FatalDeploymentError, rollout_annotation_err_msg
      end
    end

    def deploy_failed?
      @latest_rs&.deploy_failed? &&
      observed_generation == current_generation
    end

    def failure_message
      return unless @latest_rs.present?
      "Latest ReplicaSet: #{@latest_rs.name}\n\n#{@latest_rs.failure_message}"
    end

    def timeout_message
      reason_msg = if timeout_override
        STANDARD_TIMEOUT_MESSAGE
      elsif progress_condition.present?
        "Timeout reason: #{progress_condition['reason']}"
      else
        "Timeout reason: hard deadline for #{type}"
      end
      return reason_msg unless @latest_rs.present?
      "#{reason_msg}\nLatest ReplicaSet: #{@latest_rs.name}\n\n#{@latest_rs.timeout_message}"
    end

    def pretty_timeout_type
      if timeout_override
        "timeout override: #{timeout_override}s"
      elsif progress_deadline.present?
        "progress deadline: #{progress_deadline}s"
      else
        super
      end
    end

    def deploy_timed_out?
      return false if deploy_failed?
      return super if timeout_override

      # Do not use the hard timeout if progress deadline is set
      progress_condition.present? ? deploy_failing_to_progress? : super
    end

    def validate_definition(*)
      super

      unless REQUIRED_ROLLOUT_TYPES.include?(required_rollout) || percent?(required_rollout)
        @validation_errors << rollout_annotation_err_msg
      end

      strategy = @definition.dig('spec', 'strategy', 'type').to_s
      if required_rollout.downcase == 'maxunavailable' && strategy.present? && strategy.downcase != 'rollingupdate'
        @validation_errors << "'#{krane_annotation_key(REQUIRED_ROLLOUT_ANNOTATION_SUFFIX)}: #{required_rollout}' "\
          "is incompatible with strategy '#{strategy}'"
      end

      @validation_errors.empty?
    end

    private

    def current_generation
      return -2 unless exists? # different default than observed
      @instance_data.dig('metadata', 'generation')
    end

    def observed_generation
      return -1 unless exists? # different default than current
      @instance_data.dig('status', 'observedGeneration')
    end

    def desired_replicas
      return -1 unless exists?
      @instance_data["spec"]["replicas"].to_i
    end

    def rollout_data
      return { "replicas" => 0 } unless exists?
      { "replicas" => 0 }.merge(@instance_data["status"]
        .slice("replicas", "updatedReplicas", "availableReplicas", "unavailableReplicas"))
    end

    def progress_condition
      return unless exists?
      conditions = @instance_data.fetch("status", {}).fetch("conditions", [])
      conditions.find { |condition| condition['type'] == 'Progressing' }
    end

    def progress_deadline
      if exists?
        @instance_data['spec']['progressDeadlineSeconds']
      else
        @definition['spec']['progressDeadlineSeconds']
      end
    end

    def rollout_annotation_err_msg
      "'#{krane_annotation_key(REQUIRED_ROLLOUT_ANNOTATION_SUFFIX)}: #{required_rollout}' is invalid. "\
        "Acceptable values: #{REQUIRED_ROLLOUT_TYPES.join(', ')}"
    end

    def deploy_failing_to_progress?
      return false unless progress_condition.present?

      # This assumes that when the controller bumps the observed generation, it also updates/clears all the status
      # conditions. Specifically, it assumes the progress condition is immediately set to True if a rollout is starting.
      deploy_started? &&
      current_generation == observed_generation &&
      progress_condition["status"] == 'False'
    end

    def find_latest_rs(cache)
      all_rs_data = cache.get_all(ReplicaSet.kind, @instance_data["spec"]["selector"]["matchLabels"])
      current_revision = @instance_data["metadata"]["annotations"]["deployment.kubernetes.io/revision"]

      latest_rs_data = all_rs_data.find do |rs|
        rs["metadata"]["ownerReferences"].any? { |ref| ref["uid"] == @instance_data["metadata"]["uid"] } &&
        rs["metadata"]["annotations"]["deployment.kubernetes.io/revision"] == current_revision
      end

      return unless latest_rs_data.present?

      rs = ReplicaSet.new(
        namespace: namespace,
        context: context,
        definition: latest_rs_data,
        logger: @logger,
        parent: "#{@name.capitalize} deployment",
        deploy_started_at: @deploy_started_at
      )
      rs.sync(cache)
      rs
    end

    def min_available_replicas
      if percent?(required_rollout)
        (desired_replicas * required_rollout.to_i / 100.0).ceil
      elsif max_unavailable =~ /%/
        (desired_replicas * (100 - max_unavailable.to_i) / 100.0).ceil
      else
        desired_replicas - max_unavailable.to_i
      end
    end

    def max_unavailable
      source = exists? ? @instance_data : @definition
      source.dig('spec', 'strategy', 'rollingUpdate', 'maxUnavailable')
    end

    def required_rollout
      krane_annotation_value("required-rollout") || DEFAULT_REQUIRED_ROLLOUT
    end

    def percent?(value)
      value =~ /\d+%/
    end
  end
end
