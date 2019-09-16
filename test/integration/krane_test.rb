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

  private

  def fetch_restarted_at(deployment_name)
    deployment = v1beta1_kubeclient.get_deployment(deployment_name, @namespace)
    containers = deployment.spec.template.spec.containers
    app_container = containers.find { |c| c["name"] == "app" }
    app_container&.env&.find { |n| n.name == "RESTARTED_AT" }
  end
end
