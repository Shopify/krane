# frozen_string_literal: true
require 'test_helper'

class CustomResourceDefinitionTest < KubernetesDeploy::TestCase
  include ResourceCacheTestHelper

  def test_rollout_config_nil_when_none_present
    crd = build_crd(crd_spec)
    refute(crd.rollout_config)
  end

  def test_rollout_config_uses_defaults_when_not_specified
    crd = build_crd(merge_rollout_annotation('true'))

    assert(crd.rollout_config)
    assert(crd.rollout_config.success_queries)
    assert(crd.rollout_config.failure_queries)
  end

  def test_arbitrary_rollout_config
    rollout_config = {
      success_queries: [
        {
          path: "$.test_path",
          value: "test_value",
        },
      ],
      failure_queries: [
        {
          path: "$.test_path",
          value: "#.test_value",
        }
      ]
    }.to_json
    crd = build_crd(merge_rollout_annotation(rollout_config))
    crd.validate_definition(kubectl)
    refute(crd.validation_failed?, "Valid rollout config failed validation")
    
  end

  def test_rollout_config_raises_when_no_queries_specified
    missing_keys = {
      success_queries: [],
      failure_queries: [],
    }.to_json

    crd = build_crd(merge_rollout_annotation(missing_keys))
    crd.validate_definition(kubectl)
    assert(crd.validation_failed?, "Missing value in success_query should fail validation")
    assert_equal(crd.validation_error_msg, "success_queries must contain at least one entry\n" \
      "failure_queries must contain at least one entry"
    )
  end

  def test_rollout_config_raises_when_missing_query_keys
    missing_keys = {}.to_json

    crd = build_crd(merge_rollout_annotation(missing_keys))
    crd.validate_definition(kubectl)
    assert(crd.validation_failed?, "Missing value in success_query should fail validation")
    assert_equal(crd.validation_error_msg, "Missing required top-level key(s): [:success_queries, :failure_queries]\n" \
      "success_queries should be Array but found NilClass!\nfailure_queries should be Array but found NilClass!"
    )
  end

  def test_rollout_config_raises_error_with_invalid_json
    crd = build_crd(merge_rollout_annotation('bad string'))
    crd.validate_definition(kubectl)
    assert(crd.validation_failed?, "Invalid rollout config was accepted")
    assert(crd.validation_error_msg.match(/Error parsing rollout config/))
  end

  private

  def kubectl
    @kubectl ||= build_runless_kubectl
  end

  def crd_spec
    @crd_spec ||= YAML.load_file(File.join(fixture_path('for_unit_tests'), 'crd_test.yml'))
  end

  def merge_rollout_annotation(rollout_config)
    crd_spec.merge(
      "metadata" => {
        "name" => "unittests.stable.example.io",
        "annotations" => {
          KubernetesDeploy::CustomResourceDefinition::ROLLOUT_CONFIG_ANNOTATION => rollout_config,
        },
      },
    )
  end

  def build_crd(spec)
    KubernetesDeploy::CustomResourceDefinition.new(namespace: 'test', context: 'nope',
      definition: spec, logger: @logger)
  end
end
