# frozen_string_literal: true
require 'test_helper'

class ReplicaSetTest < Krane::TestCase
  include ResourceCacheTestHelper

  def test_deploy_succeeded_is_true_when_generation_and_replica_counts_match
    template = build_rs_template(status: { "observedGeneration": 2 })
    rs = build_synced_rs(template: template)
    assert_predicate(rs, :deploy_succeeded?)
  end

  def test_deploy_succeeded_not_fooled_by_stale_status
    template = build_rs_template(status: { "observedGeneration": 1 })
    rs = build_synced_rs(template: template)
    refute_predicate(rs, :deploy_succeeded?)
  end

  def test_deploy_failed_ensures_controller_has_observed_deploy
    template = build_rs_template(status: { "observedGeneration": 1, "readyReplicas": 0, "availableReplicas": 0 })
    rs = build_synced_rs(template: template)
    rs.stubs(:pods).returns([stub(deploy_failed?: true)])
    refute_predicate(rs, :deploy_failed?)
  end

  private

  def build_rs_template(status: {})
    rs_fixture.dup.deep_merge("status" => status)
  end

  def build_synced_rs(template:)
    stub_kind_get("Pod")
    rs = Krane::ReplicaSet.new(namespace: "test", context: "nope", logger: logger, definition: template)
    stub_kind_get("ReplicaSet", items: [template])
    rs.sync(build_resource_cache)
    rs
  end

  def rs_fixture
    @rs_fixture ||= YAML.load_stream(
      File.read(File.join(fixture_path('for_unit_tests'), 'replica_set_test.yml'))
    ).find { |fixture| fixture["kind"] == "ReplicaSet" }
  end
end
