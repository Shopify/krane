# frozen_string_literal: true
module KubernetesDeploy
  class CustomResourceDefinition < KubernetesResource
    TIMEOUT = 2.minutes
    ROLLOUT_CONFIG_ANNOTATION = "kubernetes-deploy.shopify.io/monitor-instance-rollout"
    GLOBAL = true

    class RolloutConfig
      attr_reader :success_queries, :failure_queries

      def initialize(rollout_config)
        config_json = JSON.parse(rollout_config)
        config = {
          success_queries: config_json["success_queries"] || default_success_query,
          failure_queries: config_json["failure_queries"] || default_failure_query,
        }.deep_symbolize_keys

        # Preemptively create JsonPath objects
        config[:success_queries].map! do |query|
          query.update(query) { |k, v| k == :path ? JsonPath.new(v) : v }
        end
        config[:failure_queries].map! do |query|
          query.update(query) { |k, v| k == :path || k == :error_msg_path ? JsonPath.new(v) : v }
        end

        validate_config(config)
        @success_queries = config[:success_queries]
        @failure_queries = config[:failure_queries]
      rescue JSON::ParserError
        raise FatalDeploymentError, "custom rollout params are not valid JSON: '#{rollout_config}'"
      rescue RuntimeError => e
        raise FatalDeploymentError, "error creating jsonpath objects, failed with: #{e}"
      end

      def deploy_succeeded?(instance_data)
        @success_queries.all? do |query|
          query[:path].on(instance_data).first == query[:value]
        end
      end

      def deploy_failed?(instance_data)
        @failure_queries.any? do |query|
          query[:path].on(instance_data).first == query[:value]
        end
      end

      def failure_messages(instance_data)
        @failure_queries.map do |query|
          next unless query[:path].on(instance_data).first == query[:value]
          if query[:custom_error_msg]
            query[:custom_error_msg]
          elsif query[:error_msg_path]
            query[:error_msg_path]&.on(instance_data)&.first
          end
        end.compact
      end

      private

      def validate_config(config)
        unless config[:success_queries].all? { |query| query[:path] && query[:value] } &&
          config[:failure_queries].all? { |query| query[:path] && query[:value] }
          raise FatalDeploymentError,
            "all success_queries and failure_queries for custom resources must have a ' +
            'path' and 'value' key that is a valid jsonpath expression"
        end
      end

      def default_success_query
        [{
          path: '$.status.conditions[?(@.type == "Ready")].status',
          value: "True",
        }]
      end

      def default_failure_query
        [{
          path: '$.status.conditions[?(@.type == "Failed")].status',
          value: "True",
          error_msg_path: '$.status.conditions[?(@.type == "Failed")].message',
        }]
      end
    end

    def deploy_succeeded?
      names_accepted_status == "True"
    end

    def deploy_failed?
      names_accepted_status == "False"
    end

    def timeout_message
      "The names this CRD is attempting to register were neither accepted nor rejected in time"
    end

    def status
      if !exists?
        super
      elsif deploy_succeeded?
        "Names accepted"
      else
        "#{names_accepted_condition['reason']} (#{names_accepted_condition['message']})"
      end
    end

    def group_version_kind
      group = @definition.dig("spec", "group")
      version = @definition.dig("spec", "version")
      "#{group}/#{version}/#{kind}"
    end

    def kind
      @definition.dig("spec", "names", "kind")
    end

    def prunable?
      prunable = @definition.dig("metadata", "annotations", "kubernetes-deploy.shopify.io/prunable")
      prunable == "true"
    end

    def rollout_config
      @rollout_config ||= RolloutConfig.new(rollout_config_string) if rollout_config_string.present?
    end

    private

    def names_accepted_condition
      conditions = @instance_data.dig("status", "conditions") || []
      conditions.detect { |c| c["type"] == "NamesAccepted" } || {}
    end

    def names_accepted_status
      names_accepted_condition["status"]
    end

    def rollout_config_string
      @definition.dig("metadata", "annotations", ROLLOUT_CONFIG_ANNOTATION)
    end
  end
end
