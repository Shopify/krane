# frozen_string_literal: true
require 'kubernetes-deploy/rollout_config'

module KubernetesDeploy
  class CustomResourceDefinition < KubernetesResource
    TIMEOUT = 2.minutes
    ROLLOUT_CONFIG_ANNOTATION = "kubernetes-deploy.shopify.io/monitor-instance-rollout"
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
      @rollout_config ||= if rollout_config_string
        config = RolloutConfig.parse_config(rollout_config_string)
        RolloutConfig.new(config)
      end
    rescue RolloutConfigError
      nil
    end

    def validate_definition(_)
      super

      RolloutConfig.parse_config(rollout_config_string) if rollout_config_string
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

    def rollout_config_string
      @definition.dig("metadata", "annotations", ROLLOUT_CONFIG_ANNOTATION)
    end
  end
end
