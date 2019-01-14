# frozen_string_literal: true
module KubernetesDeploy
  class RolloutConditionsError < StandardError
  end

  class RolloutConditions
    class << self
      def parse_conditions(conditions_string)
        return default_conditions if conditions_string.downcase == "true"

        conditions = JSON.parse(conditions_string).deep_symbolize_keys
        errors = validate_conditions(conditions)
        raise RolloutConditionsError, errors.join("\n") unless errors.empty?

        # Create JsonPath objects
        conditions[:success_conditions].each do |query|
          query[:path] = JsonPath.new(query[:path]) if query.key?(:path)
        end
        conditions[:failure_conditions].each do |query|
          query[:path] = JsonPath.new(query[:path]) if query.key?(:path)
          query[:error_msg_path] = JsonPath.new(query[:error_msg_path]) if query.key?(:error_msg_path)
        end

        conditions
      rescue RolloutConditionsError
        raise
      rescue JSON::ParserError => e
        raise RolloutConditionsError, "Error parsing rollout conditions: #{e}"
      rescue RuntimeError => e
        raise RolloutConditionsError,
          "parse_conditions encountered an unknown error." \
          "This is most likely caused by an invalid JsonPath expression. Failed with: #{e}"
      end

      def default_conditions
        {
          success_conditions: [
            {
              path: JsonPath.new('$.status.conditions[?(@.type == "Ready")].status'),
              value: "True",
            },
          ],
          failure_conditions: [
            {
              path: JsonPath.new('$.status.conditions[?(@.type == "Failed")].status'),
              value: "True",
              error_msg_path: JsonPath.new('$.status.conditions[?(@.type == "Failed")].message'),
            },
          ],
        }
      end

      private

      def validate_conditions(conditions)
        errors = []

        top_level_keys = [:success_conditions, :failure_conditions]
        missing = top_level_keys.reject { |k| conditions.key?(k) }
        unless missing.blank?
          errors << "Missing required top-level key(s): #{missing}"
        end
        remaining_keys = top_level_keys - missing
        remaining_keys.each do |k|
          errors << "#{k} should be Array but found #{conditions[k].class}!" unless [k].is_a?(Array)
          errors << "#{k} must contain at least one entry" if conditions[k].empty?
        end
        return errors unless errors.empty?

        query_keys = [:path, :value]
        conditions[:success_conditions].each do |query|
          missing = query_keys.reject { |k| query.key?(k) }
          unless missing.blank?
            errors << "Missing required key(s) for success_condition #{query}: #{missing}"
          end
        end
        conditions[:failure_conditions].each do |query|
          missing = query_keys.reject { |k| query.key?(k) }
          unless missing.blank?
            errors << "Missing required key(s) for failure_condition #{query}: #{missing}"
          end
        end
        errors
      end
    end

    def initialize(conditions)
      @success_conditions = conditions[:success_conditions]
      @failure_conditions = conditions[:failure_conditions]
    end

    def rollout_successful?(instance_data)
      @success_conditions.all? do |query|
        query[:path].first(instance_data) == query[:value]
      end
    end

    def rollout_failed?(instance_data)
      @failure_conditions.any? do |query|
        query[:path].first(instance_data) == query[:value]
      end
    end

    def failure_messages(instance_data)
      @failure_conditions.map do |query|
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
