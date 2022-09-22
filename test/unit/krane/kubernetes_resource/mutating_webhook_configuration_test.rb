# frozen_string_literal: true
require 'test_helper'

class MutatingWebhookConfigurationTest < Krane::TestCase
  def test_load_from_json
    definition = YAML.load_file(File.join(fixture_path("mutating_webhook_configurations"), "secret_hook.yaml"))
    webhook_configuration = Krane::MutatingWebhookConfiguration.new(
      namespace: 'test', context: 'nope', definition: definition,
      logger: @logger, statsd_tags: nil
    )
    assert_equal(webhook_configuration.webhooks.length, 1)

    raw_webhook = definition.dig('webhooks', 0)
    webhook = webhook_configuration.webhooks.first
    assert_equal(raw_webhook.dig('matchPolicy'), webhook.match_policy)
    assert_equal(raw_webhook.dig('sideEffects'), webhook.side_effects)

    assert_equal(webhook.rules.length, 1)
    raw_rule = definition.dig('webhooks', 0, 'rules', 0)
    rule = webhook.rules.first
    assert_equal(raw_rule.dig('apiGroups'), ['core'])
    assert_equal(rule.groups, ['core'])

    assert_equal(raw_rule.dig('apiVersions'), ['v1'])
    assert_equal(rule.versions, ['v1'])

    assert_equal(raw_rule.dig('resources'), ['secrets'])
    assert_equal(rule.resources, ['secrets'])
  end

end
