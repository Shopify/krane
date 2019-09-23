# frozen_string_literal: true
require 'integration_test_helper'

class KraneTest < KubernetesDeploy::IntegrationTest
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
