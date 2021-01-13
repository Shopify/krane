# frozen_string_literal: true
module Krane
  class CustomResourceDefinition < KubernetesResource
    TIMEOUT = 2.minutes
    ROLLOUT_CONDITIONS_ANNOTATION = "instance-rollout-conditions"
    TIMEOUT_FOR_INSTANCE_ANNOTATION = "instance-timeout"
    GLOBAL = true

    def deploy_succeeded?
      names_accepted_status == "True"
    end

    def deploy_failed?
      names_accepted_status == "False"
    end

    def timeout_message
      "The names this CRD is attempting to register were neither accepted nor rejected in time"
    end

    def timeout_for_instance
      timeout = krane_annotation_value(TIMEOUT_FOR_INSTANCE_ANNOTATION)
      DurationParser.new(timeout).parse!.to_i
    rescue DurationParser::ParsingError
      nil
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

    def group
      @definition.dig("spec", "group")
    end

    def prunable?
      prunable = krane_annotation_value("prunable")
      prunable == "true"
    end

    def predeployed?
      predeployed = krane_annotation_value("predeployed")
      predeployed.nil? || predeployed == "true"
    end

    def rollout_conditions
      return @rollout_conditions if defined?(@rollout_conditions)

      @rollout_conditions = if krane_annotation_value(ROLLOUT_CONDITIONS_ANNOTATION)
        RolloutConditions.from_annotation(krane_annotation_value(ROLLOUT_CONDITIONS_ANNOTATION))
      end
    rescue RolloutConditionsError
      @rollout_conditions = nil
    end

    def validate_definition(*, **)
      super

      validate_rollout_conditions
    rescue RolloutConditionsError => e
      @validation_errors << "Annotation #{Annotation.for(ROLLOUT_CONDITIONS_ANNOTATION)} " \
        "on #{name} is invalid: #{e}"
    end

    def validate_rollout_conditions
      if krane_annotation_value(ROLLOUT_CONDITIONS_ANNOTATION) && @rollout_conditions_validated.nil?
        conditions = RolloutConditions.from_annotation(krane_annotation_value(ROLLOUT_CONDITIONS_ANNOTATION))
        conditions.validate!
      end

      @rollout_conditions_validated = true
    end

    def sync_group_kind
      real_group = @definition.dig("apiVersion").split("/").first
      "#{self.class.kind}.#{real_group}"
    end

    private

    def names_accepted_condition
      conditions = @instance_data.dig("status", "conditions") || []
      conditions.detect { |c| c["type"] == "NamesAccepted" } || {}
    end

    def names_accepted_status
      names_accepted_condition["status"]
    end
  end
end
