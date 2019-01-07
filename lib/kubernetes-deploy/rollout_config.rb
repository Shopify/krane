# frozen_string_literal: true
module KubernetesDeploy
  class RolloutConfigError < StandardError
  end

  class RolloutConfig
    attr_reader :success_queries, :failure_queries

    class << self
      def parse_config(config_string)
        return default_config if config_string.downcase == "true"

        config = JSON.load(config_string).deep_symbolize_keys
        errors = validate_config(config)
        raise RolloutConfigError, errors.join("\n") unless errors.empty?

        # Create JsonPath objects
        config[:success_queries].map! do |query|
          query.update(query) { |k, v| k == :path ? JsonPath.new(v) : v }
        end
        config[:failure_queries].map! do |query|
          query.update(query) { |k, v| k == :path || k == :error_msg_path ? JsonPath.new(v) : v }
        end

        config
      rescue JSON::ParserError => e
        raise RolloutConfigError, "Error parsing rollout config: #{e}"
      rescue RuntimeError => e
        raise RolloutConfigError,
          "parse_config encountered an unknown error. This is most likely caused by an invalid JsonPath expression." \
          "Failed with: #{e}"
      end

      def default_config
        {
          success_queries: [
            {
              path: JsonPath.new('$.status.conditions[?(@.type == "Ready")].status'),
              value: "True",
            }
          ],
          failure_queries: [
            {
              path: JsonPath.new('$.status.conditions[?(@.type == "Failed")].status'),
              value: "True",
              error_msg_path: JsonPath.new('$.status.conditions[?(@.type == "Failed")].message'),
            }
          ]
        }
      end

      private

      def validate_config(config)
        errors = []

        top_level_keys = [:success_queries, :failure_queries]
        missing = top_level_keys.reject { |k| config[k] }
        unless missing.blank?
          errors << "Missing required top-level key(s): #{missing}"
        end
        top_level_keys.each do |k|
          errors << "#{k} should be Array but found #{config[k].class}!" unless config[k].is_a?(Array)
        end
        return errors unless errors.empty?

        errors << "success_queries must contain at least one entry" if config[:success_queries].empty?
        errors << "failure_queries must contain at least one entry" if config[:failure_queries].empty?

        query_keys = [:path, :value]
        config[:success_queries].each do |query|
          missing = query_keys.reject { |k| query[k] }
          unless missing.blank?
            errors << "Missing required key(s) for success_query #{query}: #{missing}"
          end
        end
        config[:failure_queries].each do |query|
          missing = query_keys.reject { |k| query[k] }
          unless missing.blank?
            errors << "Missing required key(s) for failure_query #{query}: #{missing}"
          end
        end
        errors
      end
    end

    def initialize(config)
      @success_queries = config[:success_queries]
      @failure_queries = config[:failure_queries]
    end

    def rollout_successful?(instance_data)
      @success_queries.all? do |query|
        query[:path].first(instance_data) == query[:value]
      end
    end

    def rollout_failed?(instance_data)
      @failure_queries.any? do |query|
        query[:path].first(instance_data) == query[:value]
      end
    end

    def failure_messages(instance_data)
      @failure_queries.map do |query|
        next unless query[:path].first(instance_data) == query[:value]
        if query[:custom_error_msg]
          query[:custom_error_msg]
        elsif query[:error_msg_path]
          query[:error_msg_path]&.first(instance_data)
        end
      end.compact
    end
  end
end
