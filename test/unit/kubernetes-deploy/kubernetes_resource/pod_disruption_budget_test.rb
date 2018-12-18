# frozen_string_literal: true
require 'test_helper'

class PodDisruptionBudgetTest < KubernetesDeploy::TestCase
  include ResourceCacheTestHelper

  def test_deploy_succeeded_is_true_as_soon_as_controller_observes_new_version
    template = build_pdb_template(status: { "observedGeneration": 2 })
    pdb = build_synced_pdb(template: template)
    assert_predicate(pdb, :deploy_succeeded?)
  end

  def test_deploy_succeeded_not_fooled_by_stale_status
    template = build_pdb_template(status: { "observedGeneration": 1 })
    pdb = build_synced_pdb(template: template)
    refute_predicate(pdb, :deploy_succeeded?)
  end

  private

  def build_pdb_template(status: {})
    pdb_fixture.dup.deep_merge("status" => status)
  end

  def build_synced_pdb(template:)
    pdb = KubernetesDeploy::PodDisruptionBudget.new(namespace: "test", context: "nope",
      logger: logger, definition: template)
    stub_kind_get("PodDisruptionBudget", items: [template])
    pdb.sync(build_resource_cache)
    pdb
  end

  def pdb_fixture
    @pdb_fixture ||= YAML.load_stream(
      File.read(File.join(fixture_path('for_unit_tests'), 'pod_disruption_budget_test.yml'))
    ).find { |fixture| fixture["kind"] == "PodDisruptionBudget" }
  end
end
