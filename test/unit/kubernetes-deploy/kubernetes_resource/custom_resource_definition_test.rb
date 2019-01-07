# frozen_string_literal: true
require 'test_helper'

class CustomResourceDefinitionTest < KubernetesDeploy::TestCase
  include ResourceCacheTestHelper

  def test_rollout_config_nil_when_none_present
    crd = build_crd(crd_spec)
    refute(crd.rollout_config)
  end

  def test_rollout_config_uses_defaults_when_not_specified
    crd = build_crd(merge_rollout_annotation('{}'))

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
    }.to_json
    crd = build_crd(merge_rollout_annotation(rollout_config))
    assert(crd.rollout_config)
    assert_equal(crd.rollout_config.success_queries[0][:value], "test_value")
    assert(crd.rollout_config.failure_queries) # uses default since none specified
  end

  def test_rollout_config_raises_when_path_or_value_missing
    missing_value = {
      success_queries: [
        {
          path: "$.test_path",
        },
      ],
    }.to_json
    crd1 = build_crd(merge_rollout_annotation(missing_value))
    assert_raises(KubernetesDeploy::FatalDeploymentError) { crd1.rollout_config }

    missing_path = {
      success_queries: [
        {
          value: "test_value",
        },
      ],
    }.to_json
    crd2 = build_crd(merge_rollout_annotation(missing_path))
    assert_raises(KubernetesDeploy::FatalDeploymentError) { crd2.rollout_config }
  end

  def test_rollout_config_raises_error_with_invalid_json
    crd = build_crd(merge_rollout_annotation('bad string'))
    assert_raises(KubernetesDeploy::FatalDeploymentError) { crd.rollout_config }

    crd = build_crd(merge_rollout_annotation('{1: 2}'))
    assert_raises(KubernetesDeploy::FatalDeploymentError) { crd.rollout_config }
  end

  private

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
