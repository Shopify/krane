# frozen_string_literal: true
require 'jsonpath'
module KubernetesDeploy
  class CustomResource < KubernetesResource
    def initialize(namespace:, context:, definition:, logger:, statsd_tags: [], crd:)
      super(namespace: namespace, context: context, definition: definition,
        logger: logger, statsd_tags: statsd_tags)
      @rollout_config = crd.rollout_config
    end

    def deploy_succeeded?
      return super unless @rollout_config
      return false unless observed_generation == current_generation

      @rollout_config.deploy_succeeded?(@instance_data)
    end

    def deploy_failed?
      return super unless @rollout_config
      return false unless observed_generation == current_generation

      @rollout_config.deploy_failed?(@instance_data)
    end

    def failure_message
      messages = @rollout_config.failure_messages(@instance_data)
      messages.present? ? messages.join("\n") : "error deploying #{id}"
    end

    def type
      kind
    end

    private

    def kind
      @definition["kind"]
    end
  end
end
