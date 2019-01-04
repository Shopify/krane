# frozen_string_literal: true
module KubernetesDeploy
  class CustomResourceDefinition < KubernetesResource
    TIMEOUT = 2.minutes
    CHILD_CR_TIMEOUT_ANNOTATION = "kubernetes-deploy.shopify.io/cr-timeout-override"
    ROLLOUT_PARAMS_ANNOTATION = "kubernetes-deploy.shopify.io/cr-rollout-params"
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

    def timeout_for_children
      @definition.dig("metadata", "annotations", CHILD_CR_TIMEOUT_ANNOTATION)&.to_i
    end

    def rollout_params
      return nil unless rollout_params_string

      raw_params = JSON.parse(rollout_params_string)
      params = {
        success_queries: raw_params["success_queries"] || default_success_query,
        failure_queries: raw_params["failure_queries"] || default_failure_query,
      }.deep_symbolize_keys

      # Preemptively create JsonPath objects
      params[:success_queries].map! do |query|
        query.update(query) { |k, v| k == :path ? JsonPath.new(v) : v }
      end
      params[:failure_queries].map! do |query|
        query.update(query) { |k, v| k == :path || k == :error_msg_path ? JsonPath.new(v) : v }
      end

      validate_params(params)
      params
    rescue JSON::ParserError
      raise FatalDeploymentError, "custom rollout params are not valid JSON: '#{rollout_params_string}'"
    rescue RuntimeError => e
      raise FatalDeploymentError, "error creating jsonpath objects, failed with: #{e}"
    end

    private

    def names_accepted_condition
      conditions = @instance_data.dig("status", "conditions") || []
      conditions.detect { |c| c["type"] == "NamesAccepted" } || {}
    end

    def names_accepted_status
      names_accepted_condition["status"]
    end

    def rollout_params_string
      @definition.dig("metadata", "annotations", ROLLOUT_PARAMS_ANNOTATION)
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

    def validate_params(params)
      unless params[:success_queries].all? { |query| query[:path] && query[:value] } &&
        params[:failure_queries].all? { |query| query[:path] && query[:value] }
        raise FatalDeploymentError,
          "all success_queries and failure_queries for custom resources must have a ' +
          'path' and 'value' key that is a valid jsonpath expression"
      end
    end
  end
end
