# frozen_string_literal: true
require 'test_helper'

class ServiceTest < KubernetesDeploy::TestCase
  include ResourceCacheTestHelper

  def test_external_name_services_only_need_to_exist
    svc_def = service_fixture('external-name')
    svc = build_service(svc_def)

    stub_kind_get("Service", items: [])
    svc.sync(build_resource_cache)
    refute(svc.exists?)
    refute(svc.deploy_succeeded?)
    assert_equal("Not found", svc.status)

    stub_kind_get("Service", items: [svc_def])
    svc.sync(build_resource_cache)
    assert(svc.exists?)
    assert(svc.deploy_succeeded?)
    assert_equal("Doesn't require any endpoints", svc.status)
  end

  def test_selectorless_cluster_ip_svc
    svc_def = service_fixture('selectorless')
    svc = build_service(svc_def)

    stub_kind_get("Service", items: [svc_def])
    svc.sync(build_resource_cache)
    assert(svc.exists?)
    assert(svc.deploy_succeeded?)
    assert_equal("Doesn't require any endpoints", svc.status) # TODO: this is not strictly correct
  end

  def test_status_not_found_for_all_types_before_exist
    all_services = [
      build_service(service_fixture('external-name')),
      build_service(service_fixture('standard')),
      build_service(service_fixture('zero-replica')),
    ]

    stub_kind_get("Service", items: [])
    cache = build_resource_cache
    all_services.each { |svc| svc.sync(cache) }

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

    stub_kind_get("Service", items: [svc_def])
    stub_kind_get("Deployment", items: deployment_fixtures)
    stub_kind_get("Pod", items: [])
    stub_kind_get("StatefulSet", items: [])
    svc.sync(build_resource_cache)

    assert(svc.exists?)
    refute(svc.deploy_succeeded?)
    assert_equal("Selects 0 pods", svc.status)

    stub_kind_get("Service", items: [svc_def])
    stub_kind_get("Deployment", items: deployment_fixtures)
    stub_kind_get("Pod", items: pod_fixtures)
    stub_kind_get("StatefulSet", items: [])
    svc.sync(build_resource_cache)

    assert(svc.exists?)
    assert(svc.deploy_succeeded?)
    assert_equal("Selects at least 1 pod", svc.status)
  end

  def test_assumes_endpoints_required_when_related_deployment_not_found
    svc_def = service_fixture('standard')
    svc = build_service(svc_def)

    stub_kind_get("Service", items: [svc_def])
    stub_kind_get("Deployment", items: [])
    stub_kind_get("Pod", items: [])
    stub_kind_get("StatefulSet", items: [])
    svc.sync(build_resource_cache)

    assert(svc.exists?)
    refute(svc.deploy_succeeded?)
    assert_equal("Selects 0 pods", svc.status)
  end

  def test_services_for_zero_replica_deployments_do_not_require_endpoints
    svc_def = service_fixture('zero-replica')
    svc = build_service(svc_def)

    stub_kind_get("Service", items: [svc_def])
    stub_kind_get("Deployment", items: deployment_fixtures)
    stub_kind_get("Pod", items: [])
    stub_kind_get("StatefulSet", items: [])
    svc.sync(build_resource_cache)

    assert(svc.exists?)
    assert(svc.deploy_succeeded?)
    assert_equal("Doesn't require any endpoints", svc.status)
  end

  def test_services_for_multiple_zero_replica_deployments_do_not_require_endpoints
    svc_def = service_fixture('zero-replica-multiple')
    svc = build_service(svc_def)

    stub_kind_get("Service", items: [svc_def])
    stub_kind_get("Deployment", items: deployment_fixtures)
    stub_kind_get("Pod", items: [])
    stub_kind_get("StatefulSet", items: [])
    svc.sync(build_resource_cache)

    assert(svc.exists?)
    assert(svc.deploy_succeeded?)
    assert_equal("Doesn't require any endpoints", svc.status)
  end

  def test_services_for_zero_replica_statefulset_do_not_require_endpoints
    svc_def = service_fixture('zero-replica-statefulset')
    svc = build_service(svc_def)

    stub_kind_get("Service", items: [svc_def])
    stub_kind_get("Deployment", items: [])
    stub_kind_get("Pod", items: [])
    stub_kind_get("StatefulSet", items: stateful_set_fixtures)
    svc.sync(build_resource_cache)

    assert(svc.exists?)
    assert(svc.deploy_succeeded?)
    assert_equal("Doesn't require any endpoints", svc.status)
  end

  def test_service_finds_deployment_with_different_pod_and_workload_labels
    svc_def = service_fixture('standard-mis-matched-lables')
    svc = build_service(svc_def)

    stub_kind_get("Service", items: [svc_def])
    stub_kind_get("Deployment", items: deployment_fixtures)
    stub_kind_get("Pod", items: pod_fixtures)
    stub_kind_get("StatefulSet", items: [])
    svc.sync(build_resource_cache)

    assert(svc.exists?)
    assert(svc.deploy_succeeded?)
    assert_equal("Doesn't require any endpoints", svc.status)
  end

  def test_ensures_populated_status_for_load_balancers
    svc_def = service_fixture('standard-lb')
    svc = build_service(svc_def)

    stub_kind_get("Service", items: [svc_def])
    stub_kind_get("Deployment", items: deployment_fixtures)
    stub_kind_get("Pod", items: pod_fixtures)
    stub_kind_get("StatefulSet", items: [])
    svc.sync(build_resource_cache)

    assert_includes(svc.to_yaml, 'type: LoadBalancer')
    assert(svc.exists?)
    refute(svc.deploy_succeeded?)
    assert_equal("LoadBalancer IP address is not provisioned yet", svc.status)

    svc_def = svc_def.deep_merge('status' => {
      'loadBalancer' => {
        'ingress' => [{
          'ip' => '146.148.47.155',
        }],
      },
    })
    stub_kind_get("Service", items: [svc_def])
    stub_kind_get("Deployment", items: deployment_fixtures)
    stub_kind_get("Pod", items: pod_fixtures)
    stub_kind_get("StatefulSet", items: [])
    svc.sync(build_resource_cache)

    assert(svc.exists?)
    assert(svc.deploy_succeeded?)
    assert_equal("Selects at least 1 pod", svc.status)
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

  def stateful_set_fixtures
    fixtures.select { |f| f["kind"] == "StatefulSet" }
  end

  def pod_fixtures
    fixtures.select { |f| f["kind"] == "Pod" }
  end

  def fixtures
    @fixtures ||= YAML.load_stream(File.read(File.join(fixture_path('for_unit_tests'), 'service_test.yml')))
  end
end
