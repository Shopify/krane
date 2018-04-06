# frozen_string_literal: true
require 'test_helper'

class ServiceTest < KubernetesDeploy::TestCase
  def test_external_name_services_only_need_to_exist
    svc_def = service_fixture('external-name')
    svc = build_service(svc_def)

    stub_kubectl_response("get", "Service", "external-name", "-a", "--output=json", success: false, resp: {})
    svc.sync(build_sync_mediator)
    refute svc.exists?
    refute svc.deploy_succeeded?
    assert_equal "Not found", svc.status

    stub_kubectl_response("get", "Service", "external-name", "-a", "--output=json", resp: svc_def)
    svc.sync(build_sync_mediator)
    assert svc.exists?
    assert svc.deploy_succeeded?
    assert_equal "Doesn't require any endpoints", svc.status
  end

  def test_selectorless_cluster_ip_svc
    svc_def = service_fixture('selectorless')
    svc = build_service(svc_def)

    stub_kubectl_response("get", "Service", "selectorless", "-a", "--output=json", resp: svc_def)
    svc.sync(build_sync_mediator)
    assert svc.exists?
    assert svc.deploy_succeeded?
    assert_equal "Doesn't require any endpoints", svc.status # TODO: this is not strictly correct
  end

  def test_status_not_found_for_all_types_before_exist
    all_services = [
      build_service(service_fixture('external-name')),
      build_service(service_fixture('standard')),
      build_service(service_fixture('zero-replica'))
    ]

    stub_kubectl_response("get", "Service", "-a", "--output=json", resp: { items: [] })
    stub_kubectl_response("get", "Deployment", "-a", "--output=json", resp: { items: deployment_fixtures })
    stub_kubectl_response("get", "Pod", "-a", "--output=json", resp: { items: pod_fixtures })

    build_sync_mediator.sync(all_services)
    all_services.each do |svc|
      refute svc.exists?, "#{svc.name} should not have existed"
      refute svc.deploy_succeeded?, "#{svc.name} should not have succeeded"
      refute svc.deploy_failed?, "#{svc.name} should not have failed"
      assert_equal "Not found", svc.status, "#{svc.name} had wrong status"
    end
  end

  def test_regular_services_must_select_pods
    svc_def = service_fixture('standard')
    svc = build_service(svc_def)

    stub_kubectl_response("get", "Service", "standard", "-a", "--output=json", resp: svc_def)
    stub_kubectl_response("get", "Deployment", "-a", "--output=json", resp: { items: deployment_fixtures })
    stub_kubectl_response("get", "Pod", "-a", "--output=json", resp: { items: [] })
    svc.sync(build_sync_mediator)

    assert svc.exists?
    refute svc.deploy_succeeded?
    assert_equal "Selects 0 pods", svc.status

    stub_kubectl_response("get", "Service", "standard", "-a", "--output=json", resp: svc_def)
    stub_kubectl_response("get", "Deployment", "-a", "--output=json", resp: { items: deployment_fixtures })
    stub_kubectl_response("get", "Pod", "-a", "--output=json", resp: { items: pod_fixtures })
    svc.sync(build_sync_mediator)

    assert svc.exists?
    assert svc.deploy_succeeded?
    assert_equal "Selects at least 1 pod", svc.status
  end

  def test_assumes_endpoints_required_when_related_deployment_not_found
    svc_def = service_fixture('standard')
    svc = build_service(svc_def)

    stub_kubectl_response("get", "Service", "standard", "-a", "--output=json", resp: svc_def)
    stub_kubectl_response("get", "Deployment", "-a", "--output=json", resp: { items: [] })
    stub_kubectl_response("get", "Pod", "-a", "--output=json", resp: { items: [] })
    svc.sync(build_sync_mediator)

    assert svc.exists?
    refute svc.deploy_succeeded?
    assert_equal "Selects 0 pods", svc.status
  end

  def test_services_for_zero_replica_deployments_do_not_require_endpoints
    svc_def = service_fixture('zero-replica')
    svc = build_service(svc_def)

    stub_kubectl_response("get", "Service", "zero-replica", "-a", "--output=json", resp: svc_def)
    stub_kubectl_response("get", "Deployment", "-a", "--output=json", resp: { items: deployment_fixtures })
    stub_kubectl_response("get", "Pod", "-a", "--output=json", resp: { items: [] })
    svc.sync(build_sync_mediator)

    assert svc.exists?
    assert svc.deploy_succeeded?
    assert_equal "Doesn't require any endpoints", svc.status
  end

  private

  def build_service(definition)
    KubernetesDeploy::Service.new(namespace: 'test', context: 'test', logger: logger, definition: definition)
  end

  def service_fixture(name)
    fixtures.find { |f| f["kind"] == "Service" && f.dig('metadata', 'name') == name }
  end

  def deployment_fixtures
    fixtures.select { |f| f["kind"] == "Deployment" }
  end

  def pod_fixtures
    fixtures.select { |f| f["kind"] == "Pod" }
  end

  def build_sync_mediator
    KubernetesDeploy::SyncMediator.new(namespace: 'test', context: 'minikube', logger: logger)
  end

  def fixtures
    @fixtures ||= YAML.load_stream(File.read(File.join(fixture_path('for_unit_tests'), 'service_test.yml')))
  end
end
