# frozen_string_literal: true
require 'test_helper'
require 'kubernetes-deploy/restart_task'

class RestartTaskTest < KubernetesDeploy::IntegrationTest
  def test_restart
    assert deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb"])

    refute fetch_restarted_at("web"), "no RESTARTED_AT env on fresh deployment"

    restart = build_restart_task
    assert restart.perform(["web"])

    assert_logs_match(/Triggered `web` restart/, 1)
    assert_logs_match(/Restart of `web` deployments succeeded/, 1)

    assert fetch_restarted_at("web"), "RESTARTED_AT is present after the restart"
  end

  def test_restart_by_annotation
    assert deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb", "redis.yml"])

    refute fetch_restarted_at("web"), "no RESTARTED_AT env on fresh deployment"
    refute fetch_restarted_at("redis"), "no RESTARTED_AT env on fresh deployment"

    restart = build_restart_task
    assert restart.perform

    assert_logs_match(/Triggered `web` restart/, 1)
    assert_logs_match(/Restart of `web` deployments succeeded/, 1)

    assert fetch_restarted_at("web"), "RESTARTED_AT is present after the restart"
    refute fetch_restarted_at("redis"), "no RESTARTED_AT env on fresh deployment"
  end

  def test_restart_by_annotation_none_found
    restart = build_restart_task
    error = assert_raises(ArgumentError) do
      restart.perform
    end
    assert_match(/no deployments found in namespace/, error.to_s)
  end

  def test_restart_twice
    assert deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb"])

    refute fetch_restarted_at("web"), "no RESTARTED_AT env on fresh deployment"

    restart = build_restart_task
    assert restart.perform(["web"])

    assert_logs_match(/Triggered `web` restart/, 1)
    assert_logs_match(/Restart of `web` deployments succeeded/, 1)

    first_restarted_at = fetch_restarted_at("web")
    assert first_restarted_at, "RESTARTED_AT is present after first restart"

    Timecop.freeze(1.second.from_now) do
      assert restart.perform(["web"])
    end

    second_restarted_at = fetch_restarted_at("web")
    assert second_restarted_at, "RESTARTED_AT is present after second restart"
    refute_equal first_restarted_at.value, second_restarted_at.value
  end

  def test_restart_with_same_resource_twice
    assert deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb"])

    refute fetch_restarted_at("web"), "no RESTARTED_AT env on fresh deployment"

    restart = build_restart_task
    assert restart.perform(%w(web web))

    assert_logs_match(/Triggered `web` restart/, 1)
    assert_logs_match(/Restart of `web` deployments succeeded/, 1)

    assert fetch_restarted_at("web"), "RESTARTED_AT is present after the restart"
  end

  def test_restart_not_existing_deployment
    restart = build_restart_task
    refute restart.perform(["web"])
    assert_logs_match(/Deployment `web` not found in namespace .+. Aborting the task./)
  end

  def test_restart_one_not_existing_deployment
    assert deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb"])

    restart = build_restart_task
    refute restart.perform(%w(walrus web))

    assert_logs_match(/Deployment `walrus` not found/)
    refute fetch_restarted_at("web"), "no RESTARTED_AT env after failed restart task"
  end

  def test_restart_none
    restart = build_restart_task
    assert_raises(ArgumentError) do
      restart.perform([])
    end
  end

  def test_restart_not_existing_context
    assert_raises(KubernetesDeploy::KubeclientBuilder::ContextMissingError) do
      KubernetesDeploy::RestartTask.new(
        context: "walrus",
        namespace: @namespace,
        logger: logger
      )
    end
  end

  def test_restart_not_existing_namespace
    restart = KubernetesDeploy::RestartTask.new(
      context: KubeclientHelper::MINIKUBE_CONTEXT,
      namespace: "walrus",
      logger: logger
    )
    refute restart.perform(["web"])
    assert_logs_match("Namespace `walrus` not found in context `minikube`. Aborting the task.")
  end

  private

  def build_restart_task
    KubernetesDeploy::RestartTask.new(
      context: KubeclientHelper::MINIKUBE_CONTEXT,
      namespace: @namespace,
      logger: logger
    )
  end

  def fetch_restarted_at(deployment_name)
    deployment = v1beta1_kubeclient.get_deployment(deployment_name, @namespace)
    containers = deployment.spec.template.spec.containers
    app_container = containers.find { |c| c["name"] == "app" }
    app_container && app_container.env.find { |n| n.name == "RESTARTED_AT" }
  end
end
