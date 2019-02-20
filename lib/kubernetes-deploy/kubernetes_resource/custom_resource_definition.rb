# frozen_string_literal: true
require 'kubernetes-deploy/rollout_conditions'

module KubernetesDeploy
  class CustomResourceDefinition < KubernetesResource
    TIMEOUT = 2.minutes
    ROLLOUT_CONDITIONS_ANNOTATION = "kubernetes-deploy.shopify.io/instance-rollout-conditions"
    TIMEOUT_FOR_INSTANCE_ANNOTATION = "kubernetes-deploy.shopify.io/instance-timeout"
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
      timeout = @definition.dig("metadata", "annotations", TIMEOUT_FOR_INSTANCE_ANNOTATION)
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
      prunable = @definition.dig("metadata", "annotations", "kubernetes-deploy.shopify.io/prunable")
      prunable == "true"
    end

    def rollout_conditions
      return @rollout_conditions if defined?(@rollout_conditions)

      @rollout_conditions = if rollout_conditions_annotation
        RolloutConditions.from_annotation(rollout_conditions_annotation)
      end
    rescue RolloutConditionsError
      @rollout_conditions = nil
    end

    def validate_definition(*)
      super

      validate_rollout_conditions
    rescue RolloutConditionsError => e
      @validation_errors << "Annotation #{ROLLOUT_CONDITIONS_ANNOTATION} on #{name} is invalid: #{e}"
    end

    def validate_rollout_conditions
      if rollout_conditions_annotation && @rollout_conditions_validated.nil?
        conditions = RolloutConditions.from_annotation(rollout_conditions_annotation)
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

    def rollout_conditions_annotation
      @definition.dig("metadata", "annotations", ROLLOUT_CONDITIONS_ANNOTATION)
    end
  end
end
