# frozen_string_literal: true
module ResourceCacheTestHelper
  def stub_group_kind_get(group_kind, items: [], times: 1, use_namespace: true)
    stub_kubectl_response(
      "get",
      group_kind,
      "--chunk-size=0",
      resp: { items: items },
      kwargs: { attempts: 5, output_is_sensitive: false, use_namespace: use_namespace },
      times: times,
    )
  end

  def build_resource_cache(task_config: nil)
    task_config ||= task_config(namespace: 'test-ns').tap do |config|
      config.stubs(:group_kinds).returns(
        [
          {
            "namespaced" => false,
            "group" => "",
            "kind" => "Node",
            "group_kind" => ::Krane::KubernetesResource.combine_group_kind("", "Node"),
          },
          {
            "namespaced" => false,
            "group" => "",
            "kind" => "FakeNode",
            "group_kind" => ::Krane::KubernetesResource.combine_group_kind("", "FakeNode"),
          },
        ]
      )
    end
    Krane::ResourceCache.new(task_config)
  end
end
