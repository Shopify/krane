# frozen_string_literal: true
require 'jsonpath'
module KubernetesDeploy
  class CustomResource < KubernetesResource
    def initialize(namespace:, context:, definition:, logger:, statsd_tags: [], crd:)
      @crd = crd
      super(namespace: namespace, context: context, definition: definition,
            logger: logger, statsd_tags: statsd_tags)
    end

    def timeout
      timeout_override || super
    end

    def deploy_succeeded?
      return super unless rollout_params
      return false unless observed_generation == current_generation

      rollout_params[:success_queries].all? do |query|
        query[:path].on(@instance_data).first == query[:value]
      end
    end

    def deploy_failed?
      return super unless rollout_params
      return false unless observed_generation == current_generation

      rollout_params[:failure_queries].any? do |query|
        query[:path].on(@instance_data).first == query[:value]
      end
    end

    def failure_message
      messages = rollout_params[:failure_queries].map do |query|
        next unless query[:path].on(@instance_data).first == query[:value]
        if query[:custom_error_msg]
          query[:custom_error_msg]
        elsif query[:error_msg_path]
          query[:error_msg_path]&.on(@instance_data)&.first
        end
      end.compact
      messages.present? ? messages.join("\n") : "error deploying #{id}"
    end

    def id
      "#{kind}/#{name}"
    end

    def type
      kind
    end

    private

    def kind
      @definition["kind"]
    end

    def rollout_params
      @rollout_params ||= @crd.rollout_params
    end
  end
end
