# frozen_string_literal: true
require 'test_helper'

class IngressTest < KubernetesDeploy::TestCase
  include ResourceCacheTestHelper

  def test_ensures_populated_status_for_load_balancers
    ingress_def = ingress_fixture('test-ingress')
    ingress = build_ingress(ingress_def)

    stub_kind_get("Ingress", items: [ingress_def])
    ingress.sync(build_resource_cache)

    assert(ingress.exists?)
    refute(ingress.deploy_succeeded?)
    assert_equal("LoadBalancer IP address is not provisioned yet", ingress.status)

    ingress_def = ingress_def.deep_merge('status' => {
      'loadBalancer' => {
        'ingress' => [{
          'ip' => '146.148.47.155',
        }],
      },
    })
    stub_kind_get("Ingress", items: [ingress_def])
    ingress.sync(build_resource_cache)

    assert(ingress.exists?)
    assert(ingress.deploy_succeeded?)
    assert_equal("Created", ingress.status)
  end

  private

  def build_ingress(definition)
    KubernetesDeploy::Ingress.new(namespace: 'test', context: 'test', logger: logger, definition: definition)
  end

  def ingress_fixture(name)
    fixtures.find { |f| f["kind"] == "Ingress" && f.dig('metadata', 'name') == name }
  end

  def fixtures
    @fixtures ||= YAML.load_stream(File.read(File.join(fixture_path('for_unit_tests'), 'ingress_test.yml')))
  end
end
