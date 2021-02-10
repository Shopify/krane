# frozen_string_literal: true
module ClusterResourceDiscoveryHelper
  def mocked_cluster_resource_discovery(success: true)
    stub_raw_apis(success: success)
    Krane::ClusterResourceDiscovery.new(task_config: task_config, namespace_tags: [])
  end

  def api_raw_full_response
    File.read(File.join(fixture_path('for_unit_tests'), "api_raw.txt"))
  end

  def apis_full_response(path)
    file = "#{path.gsub('/', '_')}.txt"
    File.read(File.join(fixture_path('for_unit_tests'), "apis", file))
  end

  def stub_raw_apis(success:)
    Krane::Kubectl.any_instance.stubs(:run).with("get", "--raw", "/", attempts: 5, use_namespace: false)
      .returns([api_raw_full_response, "", stub(success?: success)])

    return unless success
    paths = JSON.parse(api_raw_full_response)['paths'].select { |p| %r{^\/api.*\/v.*$}.match(p) }
    paths.each do |path|
      Krane::Kubectl.any_instance.stubs(:run).with("get", "--raw", path, attempts: 2, use_namespace: false)
        .returns([apis_full_response(path), "", stub(success?: true)])
    end
  end
end
