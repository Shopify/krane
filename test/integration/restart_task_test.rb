# frozen_string_literal: true
require 'test_helper'
require 'kubernetes-deploy/restart_task'

class RestartTaskTest < KubernetesDeploy::IntegrationTest
  def test_restart
    deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb"])

    refute fetch_restarted_at("web"), "no RESTARTED_AT env on fresh deployment"

    restart = KubernetesDeploy::RestartTask.new(
      context: KubeclientHelper::MINIKUBE_CONTEXT,
      namespace: @namespace,
    )
    restart.perform(["web"])

    assert_logs_match(/Triggered `web` restart/, 1)
    assert_logs_match(/Restart of `web` deployments succeeded/, 1)

    assert fetch_restarted_at("web"), "RESTARTED_AT is present after the restart"
  end

  def test_restart_all
    deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb", "redis.yml"])

    refute fetch_restarted_at("web"), "no RESTARTED_AT env on fresh deployment"
    refute fetch_restarted_at("redis"), "no RESTARTED_AT env on fresh deployment"

    restart = KubernetesDeploy::RestartTask.new(
      context: KubeclientHelper::MINIKUBE_CONTEXT,
      namespace: @namespace,
    )
    restart.perform("all")

    assert_logs_match(/Triggered `web` restart/, 1)
    assert_logs_match(/Triggered `redis` restart/, 1)
    assert_logs_match(/Restart of `redis`, `web` deployments succeeded/, 1)

    assert fetch_restarted_at("web"), "RESTARTED_AT is present after the restart"
    assert fetch_restarted_at("redis"), "RESTARTED_AT is present after the restart"
  end

  def test_restart_twice
    deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb"])

    refute fetch_restarted_at("web"), "no RESTARTED_AT env on fresh deployment"

    restart = KubernetesDeploy::RestartTask.new(
      context: KubeclientHelper::MINIKUBE_CONTEXT,
      namespace: @namespace,
    )
    restart.perform(["web"])

    assert_logs_match(/Triggered `web` restart/, 1)
    assert_logs_match(/Restart of `web` deployments succeeded/, 1)

    first_restarted_at = fetch_restarted_at("web")
    assert first_restarted_at, "RESTARTED_AT is present after first restart"

    Timecop.freeze(1.second.from_now) do
      restart.perform(["web"])
    end

    second_restarted_at = fetch_restarted_at("web")
    assert second_restarted_at, "RESTARTED_AT is present after second restart"
    refute_equal first_restarted_at.value, second_restarted_at.value
  end

  def test_restart_with_same_resource_twice
    deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb"])

    refute fetch_restarted_at("web"), "no RESTARTED_AT env on fresh deployment"

    restart = KubernetesDeploy::RestartTask.new(
      context: KubeclientHelper::MINIKUBE_CONTEXT,
      namespace: @namespace,
    )
    restart.perform(%w(web web))

    assert_logs_match(/Triggered `web` restart/, 1)
    assert_logs_match(/Restart of `web` deployments succeeded/, 1)

    assert fetch_restarted_at("web"), "RESTARTED_AT is present after the restart"
  end

  def test_restart_not_existing_deployment
    restart = KubernetesDeploy::RestartTask.new(
      context: KubeclientHelper::MINIKUBE_CONTEXT,
      namespace: @namespace,
    )
    assert_raises(KubernetesDeploy::RestartTask::DeploymentNotFoundError) do
      restart.perform(["web"])
    end
  end

  def test_restart_one_not_existing_deployment
    restart = KubernetesDeploy::RestartTask.new(
      context: KubeclientHelper::MINIKUBE_CONTEXT,
      namespace: @namespace,
    )
    assert_raises(KubernetesDeploy::RestartTask::DeploymentNotFoundError) do
      restart.perform(%w(walrus web))
    end

    deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb"])
    refute fetch_restarted_at("web"), "no RESTARTED_AT env after failed restart task"
  end

  def test_restart_all_none_found
    restart = KubernetesDeploy::RestartTask.new(
      context: KubeclientHelper::MINIKUBE_CONTEXT,
      namespace: @namespace,
    )
    error = assert_raises(ArgumentError) do
      restart.perform("all")
    end
    assert_match(/no deployments found in namespace/, error.to_s)
  end

  def test_restart_none
    restart = KubernetesDeploy::RestartTask.new(
      context: KubeclientHelper::MINIKUBE_CONTEXT,
      namespace: @namespace,
    )
    assert_raises(ArgumentError) do
      restart.perform([])
    end
  end

  def test_restart_not_existing_context
    assert_raises(KubernetesDeploy::KubeclientBuilder::ContextMissingError) do
      KubernetesDeploy::RestartTask.new(
        context: "walrus",
        namespace: @namespace,
      )
    end
  end

  def test_restart_not_existing_namespace
    restart = KubernetesDeploy::RestartTask.new(
      context: KubeclientHelper::MINIKUBE_CONTEXT,
      namespace: "walrus"
    )
    error = assert_raises(KubernetesDeploy::NamespaceNotFoundError) do
      restart.perform(["web"])
    end
    assert_equal "Namespace `walrus` not found in context `minikube`. Aborting the task.", error.to_s
  end

  private

  def fetch_restarted_at(deployment_name)
    deployment = v1beta1_kubeclient.get_deployment(deployment_name, @namespace)
    containers = deployment.spec.template.spec.containers
    assert_equal 1, containers.size
    env = containers.first.env
    env && env.find { |n| n.name == "RESTARTED_AT" }
  end
end
