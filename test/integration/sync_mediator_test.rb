# frozen_string_literal: true
require 'test_helper'

class SyncMediatorTest < KubernetesDeploy::IntegrationTest
  def test_get_instance
    mediator = bulid_mediator
    name = 'hello-cloud-configmap-data'
    r = mediator.get_instance('ConfigMap', name)
    assert_equal name, r.dig('metadata', 'name')
  end

  def test_get_instance_uses_cache
    mediator = bulid_mediator
    name = 'hello-cloud-configmap-data'
    mediator.get_all('ConfigMap')

    mediator.stub :request_instance, {} do
      r = mediator.get_instance('ConfigMap', name)
      assert_equal name, r.dig('metadata', 'name')
    end
  end

  def test_get_all
    mediator = bulid_mediator
    name = 'hello-cloud-configmap-data'
    maps = mediator.get_all('ConfigMap')
    assert_equal name, maps.first.dig('metadata', 'name')
  end

  def test_get_all_with_selector
    mediator = bulid_mediator
    name = 'hello-cloud-configmap-data'
    maps = mediator.get_all('ConfigMap', "app" => "hello-cloud")
    assert_equal name, maps.first.dig('metadata', 'name')
  end

  def test_sync_calls_resource_sync
    mediator = bulid_mediator
    config_map = Minitest::Mock.new
    config_map.expect :sync, true, [mediator]
    config_map.expect :type, "ConfigMap"
    mediator.sync([config_map])
    config_map.verify
  end

  private

  def bulid_mediator
    mediator = KubernetesDeploy::SyncMediator.new(namespace: @namespace, context: KubeclientHelper::MINIKUBE_CONTEXT,
      logger: logger)
    result = deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "unmanaged-pod.yml.erb"])
    # Expect the service account is deployed before the unmanaged pod
    assert_deploy_success(result)
    mediator
  end
end
