# frozen_string_literal: true
require 'test_helper'

class ResourceCacheTest < KubernetesDeploy::TestCase
  include ResourceCacheTestHelper

  def setup
    super
    @cache = build_resource_cache
  end

  def test_get_instance_populates_the_cache_and_returns_instance_hash
    pods = build_fake_pods(2)
    stub_kind_get("FakePod", items: pods.map(&:kubectl_response), times: 1)
    assert_equal pods[0].kubectl_response, @cache.get_instance("FakePod", pods[0].name)
    assert_equal pods[1].kubectl_response, @cache.get_instance("FakePod", pods[1].name)
  end

  def test_get_instance_returns_empty_hash_if_pod_not_found
    pods = build_fake_pods(2)
    stub_kind_get("FakePod", items: pods.map(&:kubectl_response), times: 1)
    assert_equal({}, @cache.get_instance("FakePod", "bad-name"))
  end

  def test_get_instance_raises_error_if_option_set_and_pod_not_found
    pods = build_fake_pods(2)
    stub_kind_get("FakePod", items: pods.map(&:kubectl_response), times: 1)
    assert_raises(KubernetesDeploy::Kubectl::ResourceNotFoundError) do
      @cache.get_instance("FakePod", "bad-name", raise_if_not_found: true)
    end
  end

  def test_get_all_populates_cache_and_returns_array_of_instance_hashes
    configmaps = build_fake_config_maps(6)
    stub_kind_get("Configmap", items: configmaps.map(&:kubectl_response), times: 1)
    assert_equal configmaps.map(&:kubectl_response), @cache.get_all("Configmap")
  end

  def test_if_kubectl_error_then_empty_result_returned_but_not_cached
    stub_kubectl_response('get', 'FakeConfigMap', '-a', kwargs: { attempts: 5 },
      success: false, resp: { "items" => [] }, err: 'no', times: 4)

    # All of these calls should attempt the request again (see the 'times' arg above)
    assert_equal [], @cache.get_all('FakeConfigMap')
    assert_equal [], @cache.get_all('FakeConfigMap', "fake" => "false", "type" => "fakeconfigmap")
    assert_equal({}, @cache.get_instance('FakeConfigMap', build_fake_config_maps(1).first.name))
    assert_equal({}, @cache.get_instance('FakeConfigMap', build_fake_config_maps(1).first.name))
  end

  def test_get_all_with_selector_populates_full_cache_and_filters_results_returned
    all_cm = build_fake_config_maps(3)
    stub_kind_get('FakeConfigMap', items: all_cm.map(&:kubectl_response), times: 1)

    maps = @cache.get_all('FakeConfigMap', "name" => all_cm[2].name)
    assert_equal 1, maps.length
    assert_equal all_cm[2].kubectl_response, maps.first

    maps = @cache.get_all('FakeConfigMap', "fake" => "true", "type" => "fakeconfigmap")
    assert_equal 3, maps.length

    maps = @cache.get_all('FakeConfigMap', "fake" => "false", "type" => "fakeconfigmap")
    assert_equal 0, maps.length
  end

  def test_concurrently_syncing_huge_numbers_of_resources_makes_exactly_one_kubectl_call_per_kind
    deployments = build_fake_deployments(500) # these also get pods
    pods = build_fake_pods(500)
    cm = build_fake_config_maps(50)
    all_resources = deployments + pods + cm

    # Despite being split across threads, only one resource should populate the cache for each kind
    # And the results should be available to all the others
    stub_kind_get("FakeDeployment", items: deployments.map(&:kubectl_response), times: 1)
    stub_kind_get("FakePod", items: pods.map(&:kubectl_response), times: 1)
    stub_kind_get("FakeConfigMap", items: pods.map(&:kubectl_response), times: 1)

    KubernetesDeploy::Concurrency.split_across_threads(all_resources) { |r| r.sync(@cache) }
    assert all_resources.all?(&:synced?)
  end

  private

  def build_fake_pods(num)
    num.times.map { |n| FakePod.new("pod#{n}") }
  end

  def build_fake_deployments(num)
    num.times.map { |n| FakeDeployment.new("deployment#{n}") }
  end

  def build_fake_config_maps(num)
    num.times.map { |n| FakeConfigMap.new("cm#{n}") }
  end

  class MockResource
    attr_reader :name

    def initialize(name)
      @name = name
      @synced = false
    end

    def synced?
      @synced
    end

    def sync(mediator)
      mediator.get_all(kubectl_resource_type)
      mediator.get_instance(kubectl_resource_type, @name)
      @synced = true
    end

    def type
      self.class.name.demodulize
    end

    def kubectl_resource_type
      type
    end

    def kubectl_response
      {
        "metadata" => {
          "name" => @name,
          "labels" => {
            "name" => @name,
            "fake" => "true",
            "type" => type.downcase
          }
        }
      }
    end
  end

  class FakeDeployment < MockResource
    def sync(mediator)
      super
      mediator.get_all("FakePod")
    end
  end
  class FakePod < MockResource; end
  class FakeConfigMap < MockResource; end
end
