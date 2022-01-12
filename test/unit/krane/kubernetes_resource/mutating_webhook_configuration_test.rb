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

  # Note: After we drop support for K8s 1.21 this test can be removed, since webhooks must be dry-run safe.
  def test_webhook_configuration_matches_when_side_effects
    secret_def = YAML.load_file(File.join(fixture_path('hello-cloud'), 'secret.yml'))
    secret = Krane::Secret.new(namespace: 'test', context: 'nope', definition: secret_def,
      logger: @logger, statsd_tags: nil)

    definition = YAML.load_file(File.join(fixture_path("mutating_webhook_configurations"), "secret_hook.yaml"))
    webhook_configuration = Krane::MutatingWebhookConfiguration.new(
      namespace: 'test', context: 'nope', definition: definition,
      logger: @logger, statsd_tags: nil
    )
    webhook = webhook_configuration.webhooks.first
    # Note: We have to mock `has_side_effects?`, since this won't be possible with K8s 1.22+.
    webhook.stubs(:has_side_effects?).returns(true).at_least_once
    assert(webhook.has_side_effects?)
    assert(webhook.matches_resource?(secret))
    assert(webhook.matches_resource?(secret, skip_rule_if_side_effect_none: true))
    assert(webhook.matches_resource?(secret, skip_rule_if_side_effect_none: false))
  end

  # Note: After we drop support for K8s 1.21 this test can be removed, since webhooks must be dry-run safe.
  def test_matches_webhook_configuration_doesnt_match_when_no_side_effects_and_flag
    secret_def = YAML.load_file(File.join(fixture_path('hello-cloud'), 'secret.yml'))
    secret = Krane::Secret.new(namespace: 'test', context: 'nope', definition: secret_def,
      logger: @logger, statsd_tags: nil)

    definition = YAML.load_file(File.join(fixture_path("mutating_webhook_configurations"), "secret_hook.yaml"))
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

  # Note: After we drop support for K8s 1.21 this test can be removed, since webhooks must be dry-run safe.
  def test_no_match_when_policy_is_exact_and_resource_doesnt_match
    secret_def = YAML.load_file(File.join(fixture_path('hello-cloud'), 'secret.yml'))
    secret = Krane::Secret.new(namespace: 'test', context: 'nope', definition: secret_def,
      logger: @logger, statsd_tags: nil)

    definition = YAML.load_file(File.join(fixture_path("mutating_webhook_configurations"), "secret_hook.yaml"))
    webhook_configuration = Krane::MutatingWebhookConfiguration.new(
      namespace: 'test', context: 'nope', definition: definition,
      logger: @logger, statsd_tags: nil
    )

    webhook = webhook_configuration.webhooks.first
    # Note: We have to mock `has_side_effects?`, since this won't be possible with K8s 1.22+.
    webhook.stubs(:has_side_effects?).returns(true).at_least_once
    assert(webhook.matches_resource?(secret))
    webhook.expects(:match_policy).returns(Krane::MutatingWebhookConfiguration::Webhook::EXACT).at_least(1)
    assert(webhook.matches_resource?(secret))
    secret.expects(:group).returns('fake').once
    refute(webhook.matches_resource?(secret))
    secret.unstub(:group)
    secret.expects(:type).returns('fake').once
    refute(webhook.matches_resource?(secret))
  end
end
