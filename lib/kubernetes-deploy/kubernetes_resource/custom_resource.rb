# frozen_string_literal: true
require 'jsonpath'
module KubernetesDeploy
  class CustomResource < KubernetesResource
    TIMEOUT_MESSAGE_DIFFERENT_GENERATIONS = <<~MSG
      The deploy has timed out because .status.observedGeneration is different from .metadata.generation.
      Note that in order for kubernetes-deploy to begin monitoring custom resource rollouts,
      status.observedGeneration must equal metadata.generation.
    MSG

    def initialize(namespace:, context:, definition:, logger:, statsd_tags: [], crd:)
      super(namespace: namespace, context: context, definition: definition,
            logger: logger, statsd_tags: statsd_tags)
      @crd = crd
    end

    def timeout
      timeout_override || @crd.timeout_for_instance || TIMEOUT
    end

    def rollout_conditions
      @crd.rollout_conditions
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

    def type
      kind
    end

    def validate_definition(kubectl)
      super

      @crd.validate_definition(kubectl)
    end

    private

    def kind
      @definition["kind"]
    end
  end
end
