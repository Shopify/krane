# frozen_string_literal: true

module Krane
  class MutatingWebhookConfiguration < KubernetesResource
    GLOBAL = true

    class Webhook
      EQUIVALENT = 'Equivalent'
      EXACT = 'Exact'


      class Rule
        def initialize(definition)
          @definition = definition
        end

        def matches_resource?(resource, accept_equivalent:)
          groups.each do |group|
            versions.each do |version|
              resources.each do |kind|
                return true if (resource.group == group || group == '*' || accept_equivalent) &&
                  (resource.version == version || version == '*' || accept_equivalent) &&
                  (resource.type.downcase == kind.downcase.singularize || kind == "*")
              end
            end
          end
          false
        end

        def groups
          @definition.dig('apiGroups')
        end

        def versions
          @definition.dig('apiVersions')
        end

        def resources
          @definition.dig('resources')
        end
      end

      def initialize(definition)
        @definition = definition
      end

      def side_effects
        @definition.dig('sideEffects')
      end

      def has_side_effects?
        !%w(None NoneOnDryRun).include?(side_effects)
      end

      def match_policy
        @definition.dig('matchPolicy')
      end

      def matches_resource?(resource, skip_rule_if_side_effect_none: true)
        return false if skip_rule_if_side_effect_none && !has_side_effects?
        rules.any? do |rule|
          rule.matches_resource?(resource, accept_equivalent: match_policy == EQUIVALENT)
        end
      end

      def rules
        @definition.fetch('rules', []).map { |rule| Rule.new(rule) }
      end
    end

    def initialize(namespace:, context:, definition:, logger:, statsd_tags:)
      @webhooks = (definition.dig('webhooks') || []).map { |hook| Webhook.new(hook) }
      super(namespace: namespace, context: context, definition: definition,
        logger: logger, statsd_tags: statsd_tags)
    end

    TIMEOUT = 30.seconds

    def deploy_succeeded?
      exists?
    end

    def webhooks
      @definition.fetch('webhooks', []).map { |webhook| Webhook.new(webhook) }
    end
  end
end
