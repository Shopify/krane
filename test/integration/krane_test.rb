# frozen_string_literal: true
require 'integration_test_helper'

class KraneTest < KubernetesDeploy::IntegrationTest
  include EnvTestHelper

  def test_restart_black_box
    assert_deploy_success(deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb", "redis.yml"]))
    refute(fetch_restarted_at("web"), "RESTARTED_AT env on fresh deployment")
    refute(fetch_restarted_at("redis"), "RESTARTED_AT env on fresh deployment")

    out, err, status = krane_black_box("restart", "#{@namespace} #{KubeclientHelper::TEST_CONTEXT} --deployments web")
    assert_empty(out)
    assert_match("Success", err)
    assert_predicate(status, :success?)

    assert(fetch_restarted_at("web"), "no RESTARTED_AT env is present after the restart")
    refute(fetch_restarted_at("redis"), "RESTARTED_AT env is present")
  end

  def test_run_success_black_box
    assert_empty(task_runner_pods)
    assert_deploy_success(deploy_fixtures("hello-cloud", subset: ["template-runner.yml", "configmap-data.yml"]))
    template = "hello-cloud-template-runner"
    out, err, status = krane_black_box("run",
      "#{@namespace} #{KubeclientHelper::TEST_CONTEXT} --template #{template} --command ls --arguments '-a /'")
    assert_match("Success", err)
    assert_empty(out)
    assert_predicate(status, :success?)
    assert_equal(1, task_runner_pods.count)
  end

  def test_render_black_box
    # Ordered so that template requiring bindings comes first
    paths = ["test/fixtures/test-partials/partials/independent-configmap.yml.erb",
             "test/fixtures/hello-cloud/web.yml.erb"]
    data_value = rand(10_000).to_s
    bindings = "data=#{data_value}"
    test_sha = rand(10_000).to_s

    out, err, status = nil
    with_env("REVISION", test_sha) do
      out, err, status = krane_black_box("render", "-f #{paths.join(' ')} --bindings #{bindings}")
    end

    assert_predicate(status, :success?)
    assert_match("Success", err)
    assert_match(test_sha, out)
    assert_match(data_value, out)

    with_env("REVISION", test_sha) do
      out, err, status = krane_black_box("render", "-f #{paths.join(' ')}")
    end

    refute_predicate(status, :success?)
    assert_match("FAILURE", err)
    refute_match(data_value, out)
    assert_match(test_sha, out)
  end

  def test_deploy_black_box_success
    setup_template_dir("hello-cloud") do |target_dir|
      flags = "-f #{target_dir} --render-erb --bindings deployment_id=1 current_sha=123"
      out, err, status = krane_black_box("deploy", "#{@namespace} #{KubeclientHelper::TEST_CONTEXT} #{flags}")
      assert_empty(out)
      assert_match("Success", err)
      assert_predicate(status, :success?)
    end
  end

  def test_deploy_black_box_failure
    out, err, status = krane_black_box("deploy", "#{@namespace} #{KubeclientHelper::TEST_CONTEXT}")
    assert_empty(out)
    assert_match("No value provided for required options '--filenames'", err)
    refute_predicate(status, :success?)
    assert_equal(status.exitstatus, 1)
  end

  def test_deploy_black_box_timeout
    setup_template_dir("hello-cloud") do |target_dir|
      flags = "-f #{target_dir} --render-erb --bindings deployment_id=1 current_sha=123 --global-timeout=1s"
      out, err, status = krane_black_box("deploy", "#{@namespace} #{KubeclientHelper::TEST_CONTEXT} #{flags}")
      assert_empty(out)
      assert_match("TIMED OUT", err)
      refute_predicate(status, :success?)
      assert_equal(status.exitstatus, 70)
    end
  end

  def test_global_deploy_black_box_success
    setup_template_dir("globals") do |target_dir|
      flags = "-f #{target_dir} --selector app=krane"
      out, err, status = krane_black_box("global-deploy", "#{KubeclientHelper::TEST_CONTEXT} #{flags}")
      assert_empty(out)
      assert_match("Success", err)
      assert_predicate(status, :success?)
    end
  ensure
    storage_v1_kubeclient.delete_storage_class("testing-storage-class")
  end

  def test_global_deploy_black_box_failure
    setup_template_dir("resource-quota") do |target_dir|
      flags = "-f #{target_dir} --selector app=krane"
      out, err, status = krane_black_box("global-deploy", "#{KubeclientHelper::TEST_CONTEXT} #{flags}")
      assert_empty(out)
      assert_match("FAILURE", err)
      refute_predicate(status, :success?)
      assert_equal(status.exitstatus, 1)
    end
  end

  private

  def task_runner_pods
    kubeclient.get_pods(namespace: @namespace, label_selector: "name=runner,app=hello-cloud")
  end

  def fetch_restarted_at(deployment_name)
    deployment = v1beta1_kubeclient.get_deployment(deployment_name, @namespace)
    containers = deployment.spec.template.spec.containers
    app_container = containers.find { |c| c["name"] == "app" }
    app_container&.env&.find { |n| n.name == "RESTARTED_AT" }
  end
end
