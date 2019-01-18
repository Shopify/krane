# frozen_string_literal: true
require 'jsonpath'
module KubernetesDeploy
  class CustomResource < KubernetesResource
    TIMEOUT_MESSAGE_DIFFERENT_GENERATIONS = <<~MSG
      This resource's status could not be used to determine rollout success because it was still out of date
      (.metadata.generation != .status.observedGeneration).
    MSG

    def initialize(namespace:, context:, definition:, logger:, statsd_tags: [], crd:)
      super(namespace: namespace, context: context, definition: definition,
            logger: logger, statsd_tags: statsd_tags)
      @crd = crd
    end

    def timeout
      timeout_override || @crd.timeout_for_instance || TIMEOUT
    end

    def deploy_succeeded?
      return super unless rollout_conditions
      return false unless observed_generation == current_generation

      rollout_conditions.rollout_successful?(@instance_data)
    end

    def deploy_failed?
      return super unless rollout_conditions
      return false unless observed_generation == current_generation

      rollout_conditions.rollout_failed?(@instance_data)
    end

    def failure_message
      return super unless rollout_conditions
      messages = rollout_conditions.failure_messages(@instance_data)
      messages.join("\n") if messages.present?
    end

    def timeout_message
      if rollout_conditions && current_generation != observed_generation
        TIMEOUT_MESSAGE_DIFFERENT_GENERATIONS
      else
        super
      end
    end

    def status
      if !exists? || rollout_conditions.nil?
        super
      elsif deploy_succeeded?
        "Healthy"
      elsif deploy_failed?
        "Unhealthy"
      end
    end

    def type
      kind
    end

    def validate_definition(kubectl)
      super

      @crd.validate_rollout_conditions
    rescue RolloutConditionsError => e
      @validation_errors << "Annotation #{CustomResourceDefinition::ROLLOUT_CONDITIONS_ANNOTATION} " \
      "on #{@crd.name} is invalid: #{e}"
    end

    private

    def kind
      @definition["kind"]
    end

    def rollout_conditions
      @crd.rollout_conditions
    end
  end
end
