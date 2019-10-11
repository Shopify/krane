# frozen_string_literal: true
module KubernetesDeploy
  class CustomResourceDefinition < KubernetesResource
    TIMEOUT = 2.minutes
    ROLLOUT_CONDITIONS_ANNOTATION_SUFFIX = "instance-rollout-conditions"
    ROLLOUT_CONDITIONS_ANNOTATION = "krane.shopify.io/#{ROLLOUT_CONDITIONS_ANNOTATION_SUFFIX}"
    TIMEOUT_FOR_INSTANCE_ANNOTATION = "krane.shopify.io/instance-timeout"
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
      timeout = krane_annotation_value("instance-timeout")
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

    def name
      @definition.dig("metadata", "name")
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

      @rollout_conditions = if krane_annotation_value(ROLLOUT_CONDITIONS_ANNOTATION_SUFFIX)
        RolloutConditions.from_annotation(krane_annotation_value(ROLLOUT_CONDITIONS_ANNOTATION_SUFFIX))
      end
    rescue RolloutConditionsError
      @rollout_conditions = nil
    end

    def validate_definition(*)
      super

      validate_rollout_conditions
    rescue RolloutConditionsError => e
      @validation_errors << "Annotation #{krane_annotation_key(ROLLOUT_CONDITIONS_ANNOTATION_SUFFIX)} "\
        "on #{name} is invalid: #{e}"
    end

    def validate_rollout_conditions
      if krane_annotation_value(ROLLOUT_CONDITIONS_ANNOTATION_SUFFIX) && @rollout_conditions_validated.nil?
        conditions = RolloutConditions.from_annotation(krane_annotation_value(ROLLOUT_CONDITIONS_ANNOTATION_SUFFIX))
        conditions.validate!
      end

      @rollout_conditions_validated = true
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
