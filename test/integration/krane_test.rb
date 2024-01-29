# frozen_string_literal: true
require 'integration_test_helper'

class KraneTest < Krane::IntegrationTest
  def test_restart_black_box
    assert_deploy_success(
      deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb", "redis.yml"], render_erb: true)
    )
    refute(fetch_restarted_at("web"), "restart annotation on fresh deployment")
    refute(fetch_restarted_at("redis"), "restart annotation on fresh deployment")

    out, err, status = krane_black_box("restart", "#{@namespace} #{KubeclientHelper::TEST_CONTEXT} --deployments web")
    assert_empty(out)
    assert_match("Success", err)
    assert_predicate(status, :success?)

    assert(fetch_restarted_at("web"), "no restart annotation is present after the restart")
    refute(fetch_restarted_at("redis"), "restart annotation is present")
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

    out, err, status = krane_black_box("render",
      "-f #{paths.join(' ')} --bindings #{bindings} --current-sha #{test_sha}")

    assert_predicate(status, :success?)
    assert_match("Success", err)
    assert_match(test_sha, out)
    assert_match(data_value, out)

    out, err, status = krane_black_box("render", "-f #{paths.join(' ')} --current-sha #{test_sha}")

    refute_predicate(status, :success?)
    assert_match("FAILURE", err)
    refute_match(data_value, out)
    assert_match(test_sha, out)
  end

  def test_render_black_box_stdin
    file = "test/fixtures/branched/web.yml.erb"
    template = File.read(file)
    data_value = rand(10_000).to_s
    bindings = "branch=#{data_value}"
    test_sha = rand(10_000).to_s

    out, err, status = krane_black_box("render",
      "--filenames - --bindings #{bindings} --current-sha #{test_sha}", stdin: template)

    assert_predicate(status, :success?)
    assert_match("Success", err)
    assert_match(test_sha, out)
    assert_match(data_value, out)
  end

  def test_render_current_sha_cant_be_blank
    paths = ["test/fixtures/test-partials/partials/independent-configmap.yml.erb"]
    _, err, status = krane_black_box("render", "-f #{paths.join(' ')} --current-sha")
    refute_predicate(status, :success?)
    assert_match("FAILURE", err)
    assert_match("current-sha is optional but can not be blank", err)
  end

  def test_deploy_black_box_success
    setup_template_dir("hello-cloud", subset: %w(bare_replica_set.yml)) do |target_dir|
      flags = "-f #{target_dir}"
      out, err, status = krane_black_box("deploy", "#{@namespace} #{KubeclientHelper::TEST_CONTEXT} #{flags}")
      assert_empty(out)
      assert_match("Success", err)
      assert_predicate(status, :success?)
    end
  end

  def test_deploy_black_box_success_stdin
    render_out, _, render_status = krane_black_box("render",
      "-f #{fixture_path('hello-cloud')} --bindings deployment_id=1 current_sha=123")
    assert_predicate(render_status, :success?)

    out, err, status = krane_black_box("deploy", "#{@namespace} #{KubeclientHelper::TEST_CONTEXT} --filenames -",
      stdin: render_out)
    assert_empty(out)
    assert_match("Success", err)
    assert_predicate(status, :success?)
  end

  def test_deploy_black_box_failure
    out, err, status = krane_black_box("deploy", "#{@namespace} #{KubeclientHelper::TEST_CONTEXT}")
    assert_empty(out)
    assert_match("--filenames must be set and not empty", err)
    refute_predicate(status, :success?)
    assert_equal(status.exitstatus, 1)
  end

  def test_deploy_black_box_timeout
    setup_template_dir("hello-cloud", subset: %w(bare_replica_set.yml)) do |target_dir|
      flags = "-f #{target_dir} --global-timeout=0.1s"
      out, err, status = krane_black_box("deploy", "#{@namespace} #{KubeclientHelper::TEST_CONTEXT} #{flags}")
      assert_empty(out)
      assert_match("TIMED OUT", err)
      refute_predicate(status, :success?)
      assert_equal(status.exitstatus, 70)
    end
  end

  # test_global_deploy_black_box_success and test_global_deploy_black_box_timeout
  # are in test/integration-serial/serial_deploy_test.rb because they modify
  # global state

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
    deployment = apps_v1_kubeclient.get_deployment(deployment_name, @namespace)
    deployment.spec.template.metadata.annotations&.dig(Krane::RestartTask::RESTART_TRIGGER_ANNOTATION)
  end
end
