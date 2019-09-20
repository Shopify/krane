# frozen_string_literal: true
require 'integration_test_helper'
require 'kubernetes-deploy/diff_task'

class DiffTaskTest < KubernetesDeploy::IntegrationTest
  def test_no_diff
    assert_deploy_success(deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "redis.yml"]))

    diff = build_diff_task(
      fixture_files_path("hello-cloud", files: ["configmap-data.yml", "redis.yml"])
    )
    assert_diff_success(diff.run(stream: mock_output_stream))

    assert_logs_match_all([
      "Running diff for following resources:",
      "ConfigMap/hello-cloud-configmap-data",
      /Running diff on ConfigMap .*hello-cloud-configmap-data/,
      "Local and cluster versions are identical"
      ],in_order: true
    )
  end

  def test_diff
    assert_deploy_success(deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "redis.yml"]))

    diff = build_diff_task(
      fixture_files_path("hello-cloud", files: ["configmap-data-diff.yml", "redis.yml"])
    )
    assert_diff_success(diff.run(stream: mock_output_stream))

    stdout_assertion do |output|
      assert_match("+  datapoint3: value3", output)
    end
  end

  private

  def build_diff_task(template_paths, bindings = {})
    KubernetesDeploy::DiffTask.new(
      namespace: @namespace,
      context: KubeclientHelper::TEST_CONTEXT,
      current_sha: "123",
      template_paths: template_paths,
      bindings: bindings,
      logger: logger
    )
  end
end
