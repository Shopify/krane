# frozen_string_literal: true
require 'test_helper'

class SyncMediatorTest < KubernetesDeploy::TestCase
  def setup
    super
    @fake_pod = FakePod.new('pod1')
    @fake_deployment = FakeDeployment.new('deploy1')
    @fake_cm = FakeConfigMap.new('cm1')
    @fake_cm2 = FakeConfigMap.new('cm2')
  end

  def test_get_instance_retrieves_the_resource_and_leaves_the_cache_alone_when_cache_is_empty
    stub_instance_get('FakeConfigMap', @fake_cm.name, resp: @fake_cm.kubectl_response)
    assert_equal @fake_cm.kubectl_response, mediator.get_instance('FakeConfigMap', @fake_cm.name)

    # get_instance shouldn't populate the cache, so these new calls should make new requests and return correct results
    stub_instance_get('FakeConfigMap', 'does-not-exist')
    assert_equal({}, mediator.get_instance('FakeConfigMap', 'does-not-exist'))

    stub_instance_get('FakeConfigMap', @fake_cm2.name, resp: @fake_cm2.kubectl_response)
    assert_equal @fake_cm2.kubectl_response, mediator.get_instance('FakeConfigMap', @fake_cm2.name)
  end

  def test_get_instance_uses_cache_when_available
    resp = { "items" => [@fake_cm.kubectl_response, @fake_cm2.kubectl_response] }
    stub_kind_get('FakeConfigMap', resp: resp)
    mediator.get_all('FakeConfigMap')

    # Only configmap is cached, so we should still make a request and get a result for a Deployment
    stub_instance_get('FakeDeployment', @fake_deployment.name, resp: @fake_deployment.kubectl_response)
    uncached = mediator.get_instance('FakeDeployment', @fake_deployment.name)
    assert_equal @fake_deployment.name, uncached.dig('metadata', 'name')

    # Configmap is cached, so no new requests should happen here
    mediator.kubectl.expects(:run).never
    r = mediator.get_instance('FakeConfigMap', @fake_cm.name)
    assert_equal @fake_cm.name, r.dig('metadata', 'name')
    missing = mediator.get_instance('FakeConfigMap', 'does-not-exist')
    assert_equal({}, missing)
  end

  def test_get_all_populates_cache_and_returns_array_of_instance_hashes
    expected = [@fake_cm.kubectl_response, @fake_cm2.kubectl_response]
    stub_kind_get('FakeConfigMap', resp: { "items" => expected }, times: 1)
    assert_equal expected, mediator.get_all('FakeConfigMap')
    assert_equal expected, mediator.get_all('FakeConfigMap') # cached
    assert_equal expected, mediator.get_all('FakeConfigMap') # cached
  end

  def test_get_all_does_not_cache_error_result_from_kubectl
    stub_kubectl_response('get', 'FakeConfigMap', '-a', kwargs: { attempts: 1 },
      success: false, resp: { "items" => [] }, err: 'no').times(2)
    stub_instance_get('FakeConfigMap', @fake_cm.name, resp: @fake_cm.kubectl_response, times: 1)

    # Neither the main code path nor the selector-based code path should cause error results to be cached
    assert_equal [], mediator.get_all('FakeConfigMap')
    assert_equal [], mediator.get_all('FakeConfigMap', "fake" => "false", "type" => "fakeconfigmap")
    assert_equal @fake_cm.kubectl_response, mediator.get_instance('FakeConfigMap', @fake_cm.name)
  end

  def test_get_all_with_selector_populates_full_cache_and_filters_results_returned
    all_cm = [@fake_cm.kubectl_response, @fake_cm2.kubectl_response]
    stub_kind_get('FakeConfigMap', resp: { "items" => all_cm }, times: 1) # cache used

    maps = mediator.get_all('FakeConfigMap', "name" => @fake_cm2.name)
    assert_equal 1, maps.length
    assert_equal @fake_cm2.kubectl_response, maps.first

    maps = mediator.get_all('FakeConfigMap', "fake" => "true", "type" => "fakeconfigmap")
    assert_equal 2, maps.length

    maps = mediator.get_all('FakeConfigMap', "fake" => "false", "type" => "fakeconfigmap")
    assert_equal 0, maps.length
  end

  def test_sync_clears_the_cache_and_repopulates_only_based_on_instances_given
    all_cm = [@fake_cm.kubectl_response, @fake_cm2.kubectl_response]
    stub_kind_get('FakeConfigMap', resp: { "items" => all_cm }, times: 2)
    mediator.get_all('FakeConfigMap') # makes a call
    mediator.get_instance('FakeConfigMap', @fake_cm.name) # cached

    mediator.sync([]) # no instances, so no api calls from this
    mediator.get_all('FakeConfigMap') # makes a call
    mediator.get_instance('FakeConfigMap', @fake_cm.name) # cached
  end

  def test_sync_caches_the_types_of_the_instances_given
    all_cm = [@fake_cm.kubectl_response, @fake_cm2.kubectl_response]
    stub_kind_sync('FakeConfigMap', resp: { "items" => all_cm }, times: 1)
    stub_kind_sync('FakePod', resp: { "items" => [@fake_pod.kubectl_response] }, times: 1)
    # Cache is only warmed if we batch fetch
    mediator.sync([@fake_cm, @fake_pod])

    # These should use the warm cache
    assert_equal @fake_cm.kubectl_response, mediator.get_instance('FakeConfigMap', @fake_cm.name)
    maps = mediator.get_all('FakeConfigMap')
    assert_equal 2, maps.length

    assert_predicate mediator.get_instance('FakePod', 'missing'), :empty?
    pods = mediator.get_all('FakePod')
    assert_equal 1, pods.length
  end

  def test_sync_caches_the_types_of_the_dependencies_of_the_instances_given
    stub_kind_sync('FakeDeployment', resp: { "items" => [@fake_deployment.kubectl_response] }, times: 1)
    stub_kind_sync('FakePod', resp: { "items" => [@fake_pod.kubectl_response] }, times: 1)
    # Dependency fetching is only done if we batch fetch
    # pod is a depedency so should get cached too
    mediator.sync([@fake_deployment])

    assert_equal @fake_deployment.kubectl_response, mediator.get_instance('FakeDeployment', @fake_deployment.name)
    assert_equal @fake_pod.kubectl_response, mediator.get_instance('FakePod', @fake_pod.name)
    assert_predicate mediator.get_instance('FakePod', 'missing'), :empty?
  end

  def test_calling_instance_sync_does_not_allow_instances_to_affect_the_global_cache
    # this fails if you don't dup the mediator before passing it to the instances
    bad_citizen = BadCitizen.new('foo')
    stub_kind_sync('BadCitizen', resp: { "items" => [bad_citizen.kubectl_response] }, times: 1)

    # Cache is only warmed if we batch fetch
    mediator.sync([bad_citizen])
    assert_equal bad_citizen.kubectl_response, mediator.get_instance('BadCitizen', bad_citizen.name) # still cached
  end

  def test_sync_calls_sync_on_each_instance
    test_resources = [@fake_pod, @fake_cm, @fake_deployment]
    test_resources.each { |r| r.expects(:sync).once }
    stub_kind_sync("FakePod")
    stub_kind_sync("FakeDeployment")
    stub_kind_sync("FakeConfigMap")
    mediator.sync(test_resources)
  end

  def test_sync_uses_kubectl_resource_type
    hpa = FakeHPA.new('fake')
    stub_kind_sync(hpa.kubectl_resource_type, times: 1)
    mediator.sync([hpa])
  end

  private

  def stub_instance_get(kind, name, resp: {}, times: 1)
    kwargs = { raise_if_not_found: false }
    stub_kubectl_response("get", kind, name, "-a", resp: resp, kwargs: kwargs, times: times)
  end

  def stub_kind_get(kind, resp: { items: [] }, times: 1, attempts: 1)
    kwargs = { attempts: attempts }
    stub_kubectl_response("get", kind, "-a", resp: resp, kwargs: kwargs, times: times)
  end

  def stub_kind_sync(kind, resp: { items: [] }, times: 1)
    stub_kind_get(kind, resp: resp, times: times, attempts: 5)
  end

  def mediator
    @mediator ||= KubernetesDeploy::SyncMediator.new(namespace: 'test-ns', context: KubeclientHelper::TEST_CONTEXT,
      logger: logger)
  end

  class MockResource
    attr_reader :name

    def initialize(name)
      @name = name
    end

    def sync(*)
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
    SYNC_DEPENDENCIES = %w(FakePod)
  end
  class FakePod < MockResource; end
  class FakeConfigMap < MockResource; end

  class BadCitizen < MockResource
    def sync(mediator)
      mediator.sync([]) # clears the cache
    end
  end

  class FakeHPA < MockResource
    def kubectl_resource_type
      'Not-HPA-Type'
    end
  end
end
