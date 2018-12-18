# frozen_string_literal: true
require 'test_helper'

class StatefulSetTest < KubernetesDeploy::TestCase
  include ResourceCacheTestHelper

  def test_deploy_succeeded_is_true_when_revision_and_replica_counts_match
    template = build_ss_template(status: { "observedGeneration": 2 })
    ss = build_synced_ss(template: template)
    assert_predicate(ss, :deploy_succeeded?)
  end

  def test_deploy_failed_ensures_controller_has_observed_deploy
    template = build_ss_template(status: { "observedGeneration": 1 })
    ss = build_synced_ss(template: template)
    refute_predicate(ss, :deploy_succeeded?)
  end

  def test_deploy_failed_not_fooled_by_stale_status
    status = {
      "observedGeneration": 1,
      "readyReplicas": 0,
    }
    template = build_ss_template(status: status)
    ss = build_synced_ss(template: template)
    ss.stubs(:pods).returns([stub(deploy_failed?: true)])
    refute_predicate(ss, :deploy_failed?)
  end

  private

  def build_ss_template(status: {})
    ss_fixture.dup.deep_merge("status" => status)
  end

  def build_synced_ss(template:)
    ss = KubernetesDeploy::StatefulSet.new(namespace: "test", context: "nope", logger: logger, definition: template)
    stub_kind_get("StatefulSet", items: [template])
    stub_kind_get("Pod", items: [])
    ss.sync(build_resource_cache)
    ss
  end

  def ss_fixture
    @ss_fixture ||= YAML.load_stream(
      File.read(File.join(fixture_path('for_unit_tests'), 'stateful_set_test.yml'))
    ).find { |fixture| fixture["kind"] == "StatefulSet" }
  end
end
