# frozen_string_literal: true
require 'test_helper'

class CustomResourceDefinitionTest < KubernetesDeploy::TestCase
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
    refute(crd.validation_failed?, "Valid rollout conditions failed validation")
  end

  def test_rollout_conditions_failure_conditions_optional
    rollout_conditions = {
      success_conditions: [
        {
          path: "$.test_path",
          value: "test_value",
        },
      ],
    }.to_json

    crd = build_crd(merge_rollout_annotation(rollout_conditions))
    crd.validate_definition(kubectl)
    refute(crd.validation_failed?, "Valid rollout conditions failed validation")
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
      "Annotation #{KubernetesDeploy::CustomResourceDefinition::ROLLOUT_CONDITIONS_ANNOTATION} " \
      "on #{crd.name} is invalid: Missing required key(s) for success_condition: [:value], " \
      "Missing required key(s) for failure_condition: [:path]")
  end

  def test_rollout_conditions_fails_validation_when_missing_condition_keys
    missing_keys = { success_conditions: [] }.to_json

    crd = build_crd(merge_rollout_annotation(missing_keys))
    crd.validate_definition(kubectl)

    assert(crd.validation_failed?, "success_conditions requires at least one entry")
    assert_equal(crd.validation_error_msg,
      "Annotation #{KubernetesDeploy::CustomResourceDefinition::ROLLOUT_CONDITIONS_ANNOTATION} " \
      "on #{crd.name} is invalid: success_conditions must contain at least one entry")
  end

  def test_rollout_conditions_fails_validation_with_invalid_json
    crd = build_crd(merge_rollout_annotation('bad string'))
    crd.validate_definition(kubectl)
    assert(crd.validation_failed?, "Invalid rollout conditions were accepted")
    assert(crd.validation_error_msg.match(
      "Annotation #{KubernetesDeploy::CustomResourceDefinition::ROLLOUT_CONDITIONS_ANNOTATION} " \
      "on #{crd.name} is invalid: Rollout conditions are not valid JSON:"
    ))
  end

  def test_rollout_conditions_fails_validation_when_condition_is_wrong_type
    crd = build_crd(merge_rollout_annotation({
      success_conditions: {},
    }.to_json))
    crd.validate_definition(kubectl)
    assert(crd.validation_failed?, "Invalid rollout conditions were accepted")
    assert(crd.validation_error_msg.match("success_conditions should be Array but found Hash"))
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
    assert(cr.validation_error_msg.include?(
      "The CRD that specifies this resource is using invalid rollout conditions. Kubernetes-deploy will not be " \
      "able to continue until those rollout conditions are fixed.\nRollout conditions can be found on the CRD " \
      "that defines this resource (unittests.stable.example.io), under the annotation " \
      "krane.shopify.io/instance-rollout-conditions.\nValidation failed with: " \
      "Rollout conditions are not valid JSON:"
    ))
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
      logger: @logger, statsd_tags: [], crd: crd,
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
      logger: @logger, statsd_tags: [], crd: crd,
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
      logger: @logger, statsd_tags: [], crd: crd,
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
      logger: @logger, statsd_tags: [], crd: crd,
      definition: {
        "kind" => "UnitTest",
        "metadata" => {
          "name" => "test",
        },
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
      logger: @logger, statsd_tags: [], crd: crd,
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
