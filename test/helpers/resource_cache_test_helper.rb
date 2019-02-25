# frozen_string_literal: true
module ResourceCacheTestHelper
  def stub_kind_get(kind, items: [], times: 1)
    stub_kubectl_response(
      "get",
      kind,
      "--chunk-size=0",
      resp: { items: items },
      kwargs: { attempts: 5, output_is_sensitive: false },
      times: times,
    )
  end

  def build_resource_cache
    KubernetesDeploy::ResourceCache.new('test-ns', KubeclientHelper::TEST_CONTEXT, logger)
  end
end
