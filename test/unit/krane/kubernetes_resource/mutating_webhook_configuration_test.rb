# frozen_string_literal: true
require 'test_helper'

class MutatingWebhookConfigurationTest < Krane::TestCase
  def test_load_from_json
    definition = JSON.parse(
      File.read(File.join(fixture_path("for_serial_deploy_tests"), "secret_hook.json"))
    )["items"][0]
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

  def test_webhook_configuration_matches_when_side_effects
    secret_def = YAML.load_file(File.join(fixture_path('hello-cloud'), 'secret.yml'))
    secret = Krane::Secret.new(namespace: 'test', context: 'nope', definition: secret_def,
      logger: @logger, statsd_tags: nil)

    definition = JSON.parse(
      File.read(File.join(fixture_path("for_serial_deploy_tests"), "secret_hook.json"))
    )["items"][0]
    webhook_configuration = Krane::MutatingWebhookConfiguration.new(
      namespace: 'test', context: 'nope', definition: definition,
      logger: @logger, statsd_tags: nil
    )
    webhook = webhook_configuration.webhooks.first
    assert(webhook.has_side_effects?)
    assert(webhook.matches_resource?(secret))
    assert(webhook.matches_resource?(secret, skip_rule_if_side_effect_none: true))
    assert(webhook.matches_resource?(secret, skip_rule_if_side_effect_none: false))
  end

  def test_matches_webhook_configuration_doesnt_match_when_no_side_effects_and_flag
    secret_def = YAML.load_file(File.join(fixture_path('hello-cloud'), 'secret.yml'))
    secret = Krane::Secret.new(namespace: 'test', context: 'nope', definition: secret_def,
      logger: @logger, statsd_tags: nil)

    definition = JSON.parse(
      File.read(File.join(fixture_path("for_serial_deploy_tests"), "secret_hook.json"))
    )["items"][0]
    webhook_configuration = Krane::MutatingWebhookConfiguration.new(
      namespace: 'test', context: 'nope', definition: definition,
      logger: @logger, statsd_tags: nil
    )
    webhook = webhook_configuration.webhooks.first
    webhook.stubs(:has_side_effects?).returns(false).at_least_once
    refute(webhook.matches_resource?(secret))
    refute(webhook.matches_resource?(secret, skip_rule_if_side_effect_none: true))
    assert(webhook.matches_resource?(secret, skip_rule_if_side_effect_none: false))
  end
end
