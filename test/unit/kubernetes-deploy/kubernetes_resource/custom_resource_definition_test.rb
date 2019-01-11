# frozen_string_literal: true
require 'test_helper'

class CustomResourceDefinitionTest < KubernetesDeploy::TestCase
  include ResourceCacheTestHelper

  def test_rollout_conditions_nil_when_none_present
    crd = build_crd(crd_spec)
    refute(crd.rollout_conditions)
  end

  def test_arbitrary_rollout_conditions
    rollout_conditions = {
      success_conditions: [
        {
          path: "$.test_path",
          value: "test_value",
        },
      ],
      failure_conditions: [
        {
          path: "$.test_path",
          value: "test_value",
        },
      ],
    }.to_json

    crd = build_crd(merge_rollout_annotation(rollout_conditions))
    crd.validate_definition(kubectl)
    refute(crd.validation_failed?, "Valid rollout config failed validation")
  end

  def test_rollout_conditions_invalid_when_path_or_value_missing
    missing_keys = {
      success_conditions: [{ path: "$.test" }],
      failure_conditions: [{ value: "test" }],
    }

    crd = build_crd(merge_rollout_annotation(missing_keys.to_json))
    crd.validate_definition(kubectl)
    assert(crd.validation_failed?, "Missing path/value keys should fail validation")
    assert_equal(crd.validation_error_msg,
      "Missing required key(s) for success_query {:path=>\"$.test\"}: [:value]\n" \
      "Missing required key(s) for failure_query {:value=>\"test\"}: [:path]")
  end

  def test_rollout_conditions_raises_when_missing_condition_keys
    missing_keys = { success_conditions: [] }.to_json

    crd = build_crd(merge_rollout_annotation(missing_keys))
    crd.validate_definition(kubectl)
    assert(crd.validation_failed?, "Missing failure_conditions key should fail validation")
    assert_equal(crd.validation_error_msg, "Missing required top-level key(s): [:failure_conditions]\n" \
      "success_conditions must contain at least one entry")
  end

  def test_rollout_conditions_raises_error_with_invalid_json
    crd = build_crd(merge_rollout_annotation('bad string'))
    crd.validate_definition(kubectl)
    assert(crd.validation_failed?, "Invalid rollout config was accepted")
    assert(crd.validation_error_msg.match(/Error parsing rollout config/))
  end

  def test_cr_instance_fails_validation_when_rollout_conditions_for_crd_invalid
    crd = build_crd(merge_rollout_annotation('bad string'))
    cr = KubernetesDeploy::KubernetesResource.build(namespace: "test", context: "test",
      logger: @logger, statsd_tags: @statsd_tags, crd: crd,
      definition: {
        "kind" => "UnitTest",
        "metadata" => { "name" => "test" },
      })
    cr.validate_definition(kubectl)
    assert(crd.validation_error_msg.match(/Error parsing rollout config/))
  end

  def test_cr_instance_valid_when_rollout_conditions_for_crd_valid
    rollout_conditions = {
      success_conditions: [
        {
          path: "$.test_path",
          value: "test_value",
        },
      ],
      failure_conditions: [
        {
          path: "$.test_path",
          value: "test_value",
        },
      ],
    }.to_json

    crd = build_crd(merge_rollout_annotation(rollout_conditions))
    cr = KubernetesDeploy::KubernetesResource.build(namespace: "test", context: "test",
      logger: @logger, statsd_tags: @statsd_tags, crd: crd,
      definition: {
        "kind" => "UnitTest",
        "metadata" => { "name" => "test" },
      })
    cr.validate_definition(kubectl)
    refute(cr.validation_failed?)
  end

  def test_instance_timeout_annotation
    crd = build_crd(crd_spec.merge(
      "metadata" => {
        "name" => "unittests.stable.example.io",
      },
    ))
    cr = KubernetesDeploy::KubernetesResource.build(namespace: "test", context: "test",
      logger: @logger, statsd_tags: @statsd_tags, crd: crd,
      definition: { "kind" => "UnitTest", "metadata" => { "name" => "test" } })
    assert_equal(cr.timeout, KubernetesDeploy::CustomResource.timeout)

    crd = build_crd(crd_spec.merge(
      "metadata" => {
        "name" => "unittests.stable.example.io",
        "annotations" => {
          KubernetesDeploy::CustomResourceDefinition::TIMEOUT_FOR_INSTANCE_ANNOTATION => "60S",
        },
      }
    ))
    cr = KubernetesDeploy::KubernetesResource.build(namespace: "test", context: "test",
      logger: @logger, statsd_tags: @statsd_tags, crd: crd,
      definition: { "kind" => "UnitTest", "metadata" => { "name" => "test" } })
    assert_equal(cr.timeout, 60)
  end

  def test_instance_timeout_messages_with_rollout_conditions
    crd = build_crd(crd_spec.merge(
      "metadata" => {
        "name" => "unittests.stable.example.io",
        "annotations" => {
          KubernetesDeploy::CustomResourceDefinition::ROLLOUT_CONDITIONS_ANNOTATION => "true",
        },
      },
    ))
    cr = KubernetesDeploy::KubernetesResource.build(namespace: "test", context: "test",
      logger: @logger, statsd_tags: @statsd_tags, crd: crd,
      definition: {
        "kind" => "UnitTest",
        "metadata" => {
          "name" => "test",
          "generation" => 1,
        },
        "status" => { "observedGeneration" => 1 },
      })

    cr.expects(:current_generation).returns(1)
    cr.expects(:observed_generation).returns(1)
    assert_equal(cr.timeout_message, KubernetesDeploy::KubernetesResource::STANDARD_TIMEOUT_MESSAGE)

    cr.expects(:current_generation).returns(1)
    cr.expects(:observed_generation).returns(2)
    assert_equal(cr.timeout_message, KubernetesDeploy::CustomResource::TIMEOUT_MESSAGE_DIFFERENT_GENERATIONS)
  end

  def test_instance_timeout_messages_without_rollout_conditions
    crd = build_crd(crd_spec.merge(
      "metadata" => {
        "name" => "unittests.stable.example.io",
      },
    ))
    cr = KubernetesDeploy::KubernetesResource.build(namespace: "test", context: "test",
      logger: @logger, statsd_tags: @statsd_tags, crd: crd,
      definition: {
        "kind" => "UnitTest",
        "metadata" => {
          "name" => "test",
        },
      })

    assert_equal(cr.timeout_message, KubernetesDeploy::KubernetesResource::STANDARD_TIMEOUT_MESSAGE)
  end

  private

  def kubectl
    @kubectl ||= build_runless_kubectl
  end

  def crd_spec
    @crd_spec ||= YAML.load_file(File.join(fixture_path('for_unit_tests'), 'crd_test.yml'))
  end

  def merge_rollout_annotation(rollout_conditions)
    crd_spec.merge(
      "metadata" => {
        "name" => "unittests.stable.example.io",
        "annotations" => {
          KubernetesDeploy::CustomResourceDefinition::ROLLOUT_CONDITIONS_ANNOTATION => rollout_conditions,
        },
      },
    )
  end

  def build_crd(spec)
    KubernetesDeploy::CustomResourceDefinition.new(namespace: 'test', context: 'nope',
      definition: spec, logger: @logger)
  end
end
