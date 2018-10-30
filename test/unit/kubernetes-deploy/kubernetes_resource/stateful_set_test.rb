# frozen_string_literal: true
require 'test_helper'

class StatefulSetTest < KubernetesDeploy::TestCase
  def test_deploy_succeeded_is_true_when_revision_and_replica_counts_match
    template = build_ss_template(status: { "observedGeneration": 2 })
    ss = build_synced_ss(template: template)
    assert_predicate ss, :deploy_succeeded?
  end

  def test_deploy_failed_ensures_controller_has_observed_deploy
    template = build_ss_template(status: { "observedGeneration": 1 })
    ss = build_synced_ss(template: template)
    refute_predicate ss, :deploy_succeeded?
  end

  def test_deploy_failed_not_fooled_by_stale_status
    status = {
      "observedGeneration": 1,
      "readyReplicas": 0,
    }
    template = build_ss_template(status: status)
    ss = build_synced_ss(template: template)
    ss.stubs(:pods).returns([stub(deploy_failed?: true)])
    refute_predicate ss, :deploy_failed?
  end

  private

  def build_ss_template(status: {})
    ss_fixture.dup.deep_merge("status" => status)
  end

  def build_synced_ss(template:)
    ss = KubernetesDeploy::StatefulSet.new(namespace: "test", context: "nope", logger: logger, definition: template)
    sync_mediator = KubernetesDeploy::SyncMediator.new(namespace: 'test', context: 'minikube', logger: logger)
    sync_mediator.kubectl.expects(:run)
      .with("get", "StatefulSet", "test-ss", "-a", "--output=json", raise_if_not_found: true)
      .returns([template.to_json, "", SystemExit.new(0)])
    sync_mediator.kubectl.expects(:run).with("get", "Pod", "-a", "--output=json", anything).returns(
      ['{ "items": [] }', "", SystemExit.new(0)]
    )
    sync_mediator.kubectl.expects(:server_version).returns(Gem::Version.new(KubernetesDeploy::MIN_KUBE_VERSION))
    ss.sync(sync_mediator)
    ss
  end

  def ss_fixture
    @ss_fixture ||= YAML.load_stream(
      File.read(File.join(fixture_path('for_unit_tests'), 'stateful_set_test.yml'))
    ).find { |fixture| fixture["kind"] == "StatefulSet" }
  end
end
