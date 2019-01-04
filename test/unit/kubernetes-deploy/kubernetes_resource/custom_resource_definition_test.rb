# frozen_string_literal: true
require 'test_helper'

class CustomResourceDefinitionTest < KubernetesDeploy::TestCase
  include ResourceCacheTestHelper

  def test_rollout_params_nil_when_none_present
    crd = build_crd(crd_spec)
    refute(crd.rollout_params)
  end

  def test_rollout_params_uses_defaults_when_not_specified
    crd = build_crd(merge_rollout_annotation('{}'))

    assert(crd.rollout_params)
    assert(crd.rollout_params[:success_queries])
    assert(crd.rollout_params[:failure_queries])
  end

  def test_arbitrary_rollout_params
    rollout_params = {
      success_queries: [
        {
          path: "$.test_path",
          value: "test_value",
        },
      ],
    }.to_json
    crd = build_crd(merge_rollout_annotation(rollout_params))
    assert(crd.rollout_params)
    assert_equal(crd.rollout_params[:success_queries][0][:value], "test_value")
    assert(crd.rollout_params[:failure_queries]) # uses default since none specified
  end

  def test_rollout_params_raises_when_path_or_value_missing
    rollout_params = {
      success_queries: [
        {
          path: "$.test_path",
        },
      ],
    }.to_json

    crd = build_crd(merge_rollout_annotation(rollout_params))
    assert_raises(KubernetesDeploy::FatalDeploymentError) { crd.rollout_params }
  end

  def test_rollout_params_raises_error_with_invalid_json
    crd = build_crd(merge_rollout_annotation('bad string'))
    assert_raises(KubernetesDeploy::FatalDeploymentError) { crd.rollout_params }

    crd = build_crd(merge_rollout_annotation('{1: 2}'))
    assert_raises(KubernetesDeploy::FatalDeploymentError) { crd.rollout_params }
  end

  private

  def crd_spec
    @crd_spec ||= YAML.load_file(File.join(fixture_path('for_unit_tests'), 'crd_test.yml'))
  end

  def merge_rollout_annotation(rollout_params)
    crd_spec.merge(
      "metadata" => {
        "name" => "unittests.stable.example.io",
        "annotations" => {
          KubernetesDeploy::CustomResourceDefinition::ROLLOUT_CONFIG_ANNOTATION.to_s => rollout_params,
        },
      },
    )
  end

  def build_crd(spec)
    KubernetesDeploy::CustomResourceDefinition.new(namespace: 'test', context: 'nope',
      definition: spec, logger: @logger)
  end
end
