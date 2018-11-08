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
      timeout_override || @crd.timeout_for_children || super
    end

    def deploy_succeeded?
      return super unless rollout_params
      rollout_params[:success_queries].all? do |query|
        JsonPath.new(query[:path]).first(@instance_data) == query[:value]
      end
    end

    def deploy_failed?
      return super unless rollout_params
      rollout_params[:failure_queries].any? do |query|
        JsonPath.new(query[:path]).first(@instance_data) == query[:value]
      end
    end

    def failure_message
      messages = rollout_params[:failure_queries].map do |query|
        next unless JsonPath.new(query[:path]).first(@instance_data) == query[:value]
        if query[:custom_error_msg]
          query[:custom_error_msg]
        else
          JsonPath.new(query[:error_msg_path]).first(@instance_data) if query[:error_msg_path]
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
