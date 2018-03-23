# frozen_string_literal: true
require 'test_helper'

class SyncMediatorTest < KubernetesDeploy::IntegrationTest

  def test_get_instance_without_cache
    mediator = bulid_mediator
    name = 'hello-cloud-configmap-data'
    r = mediator.get_instance('ConfigMap', name)
    assert_equal name, r.dig('metadata', 'name')
  end

  def test_get_instance_uses_cache
    mediator = bulid_mediator
    name = 'hello-cloud-configmap-data'
    r = mediator.get_instance('ConfigMap', name)
    assert_equal name, r.dig('metadata', 'name')
    r = mediator.get_instance('ConfigMap', name)
    assert_equal name, r.dig('metadata', 'name')
  end

  def test_get_all_without_cache
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

  def test_sync
    mediator = bulid_mediator
    name = 'hello-cloud-configmap-data'
    r = mediator.get_instance('ConfigMap', name)
    config_map = KubernetesDeploy::ConfigMap.new(namespace: nil, context: nil, definition: r, logger: logger)
    mediator.sync([config_map])
    refute "What the heck am I supposed to be testing here"
  end

  def test_sync_with_dependencies
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
