# frozen_string_literal: true
module KubernetesDeploy
  class RolloutConditionsError < StandardError
  end

  class RolloutConditions
    VALID_FAILURE_CONDITION_KEYS = [:path, :value, :error_msg_path, :custom_error_msg]
    VALID_SUCCESS_CONDITION_KEYS = [:path, :value]

    class << self
      def from_annotation(conditions_string)
        return new(default_conditions) if conditions_string.downcase.strip == "true"

        conditions = JSON.parse(conditions_string).slice('success_conditions', 'failure_conditions')
        conditions.deep_symbolize_keys!

        # Create JsonPath objects
        conditions[:success_conditions]&.each do |query|
          query.slice!(*VALID_SUCCESS_CONDITION_KEYS)
          query[:path] = JsonPath.new(query[:path]) if query.key?(:path)
        end
        conditions[:failure_conditions]&.each do |query|
          query.slice!(*VALID_FAILURE_CONDITION_KEYS)
          query[:path] = JsonPath.new(query[:path]) if query.key?(:path)
          query[:error_msg_path] = JsonPath.new(query[:error_msg_path]) if query.key?(:error_msg_path)
        end

        new(conditions)
      rescue JSON::ParserError => e
        raise RolloutConditionsError, "Rollout conditions are not valid JSON: #{e}"
      rescue StandardError => e
        raise RolloutConditionsError,
          "Error parsing rollout conditions. " \
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
    end

    def initialize(conditions)
      @success_conditions = conditions.fetch(:success_conditions, [])
      @failure_conditions = conditions.fetch(:failure_conditions, [])
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
        query[:custom_error_msg].presence || query[:error_msg_path]&.first(instance_data)
      end.compact
    end

    def validate!
      errors = validate_conditions(@success_conditions, 'success_conditions')
      errors += validate_conditions(@failure_conditions, 'failure_conditions', required: false)
      raise RolloutConditionsError, errors.join(", ") unless errors.empty?
    end

    private

    def validate_conditions(conditions, source_key, required: true)
      return [] unless conditions.present? || required
      errors = []
      errors << "#{source_key} should be Array but found #{conditions.class}" unless conditions.is_a?(Array)
      return errors if errors.present?
      errors << "#{source_key} must contain at least one entry" if conditions.empty?
      return errors if errors.present?

      conditions.each do |query|
        missing = [:path, :value].reject { |k| query.key?(k) }
        errors << "Missing required key(s) for #{source_key.singularize}: #{missing}" if missing.present?
      end
      errors
    end
  end
end
