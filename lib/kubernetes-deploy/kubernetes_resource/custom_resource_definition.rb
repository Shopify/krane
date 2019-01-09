# frozen_string_literal: true
require 'kubernetes-deploy/rollout_config'

module KubernetesDeploy
  class CustomResourceDefinition < KubernetesResource
    TIMEOUT = 2.minutes
    ROLLOUT_CONFIG_ANNOTATION = "kubernetes-deploy.shopify.io/monitor-instance-rollout"
    TIMEOUT_ANNOTATION = "kubernetes-deploy.shopify.io/cr-instance-timeout"
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
      timeout = @definition.dig("metadata", "annotations", TIMEOUT_ANNOTATION)
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

    def rollout_config
      @rollout_config ||= if rollout_config_annotation
        config = RolloutConfig.parse_config(rollout_config_annotation)
        RolloutConfig.new(config)
      end
    rescue RolloutConfigError
      nil
    end

    def validate_definition(_)
      super

      RolloutConfig.parse_config(rollout_config_annotation) if rollout_config_annotation
    rescue RolloutConfigError => e
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

    def rollout_config_annotation
      @definition.dig("metadata", "annotations", ROLLOUT_CONFIG_ANNOTATION)
    end
  end
end
