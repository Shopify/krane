# frozen_string_literal: true
module ResourceCacheTestHelper
  def stub_kind_get(kind, items: [], times: 1, use_namespace: true)
    stub_kubectl_response(
      "get",
      kind,
      "--chunk-size=0",
      resp: { items: items },
      kwargs: { attempts: 5, output_is_sensitive: false, use_namespace: use_namespace },
      times: times,
    )
  end

  def build_resource_cache(global_kinds: %w(Node FakeNode))
    config = task_config(namespace: 'test-ns')
    config.stubs(:global_kinds).returns(global_kinds) if global_kinds
    Krane::ResourceCache.new(config)
  end
end
