# frozen_string_literal: true
require 'kubernetes-deploy/rollout_conditions'

module KubernetesDeploy
  class CustomResourceDefinition < KubernetesResource
    TIMEOUT = 2.minutes
    ROLLOUT_CONDITIONS_ANNOTATION = "kubernetes-deploy.shopify.io/instance-rollout-conditions"
    TIMEOUT_FOR_INSTANCE_ANNOTATION = "kubernetes-deploy.shopify.io/cr-instance-timeout"
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

    def prunable?
      prunable = @definition.dig("metadata", "annotations", "kubernetes-deploy.shopify.io/prunable")
      prunable == "true"
    end

    def rollout_conditions
      @rollout_conditions ||= if rollout_conditions_annotation
        config = RolloutConditions.parse_config(rollout_conditions_annotation)
        RolloutConditions.new(config)
      end
    rescue RolloutConditionsError
      nil
    end

    def validate_definition(_)
      super

      RolloutConditions.parse_config(rollout_conditions_annotation) if rollout_conditions_annotation
    rescue RolloutConditionsError => e
      @validation_errors << e
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
