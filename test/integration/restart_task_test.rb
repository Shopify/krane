# frozen_string_literal: true
require 'integration_test_helper'
require 'kubernetes-deploy/restart_task'

class RestartTaskTest < KubernetesDeploy::IntegrationTest
  def test_restart_by_annotation
    assert_deploy_success(deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb", "redis.yml"]))

    refute(fetch_restarted_at("web"), "no RESTARTED_AT env on fresh deployment")
    refute(fetch_restarted_at("redis"), "no RESTARTED_AT env on fresh deployment")

    restart = build_restart_task
    assert_restart_success(restart.perform)

    assert_logs_match_all([
      "Configured to restart all deployments with the `shipit.shopify.io/restart` annotation",
      "Triggered `web` restart",
      "Waiting for rollout",
      %r{Successfully restarted in \d+\.\d+s: Deployment/web},
      "Result: SUCCESS",
      "Successfully restarted 1 resource",
      %r{Deployment/web.*1 availableReplica},
    ],
      in_order: true)

    assert(fetch_restarted_at("web"), "RESTARTED_AT is present after the restart")
    refute(fetch_restarted_at("redis"), "no RESTARTED_AT env on fresh deployment")
  end

  def test_restart_by_selector
    assert_deploy_success(deploy_fixtures("branched",
      bindings: { "branch" => "master" },
      selector: KubernetesDeploy::LabelSelector.parse("branch=master")))
    assert_deploy_success(deploy_fixtures("branched",
      bindings: { "branch" => "staging" },
      selector: KubernetesDeploy::LabelSelector.parse("branch=staging")))

    refute(fetch_restarted_at("master-web"), "no RESTARTED_AT env on fresh deployment")
    refute(fetch_restarted_at("staging-web"), "no RESTARTED_AT env on fresh deployment")

    restart = build_restart_task
    assert_restart_success(restart.perform(selector: KubernetesDeploy::LabelSelector.parse("name=web,branch=staging")))

    assert_logs_match_all([
      "Configured to restart all deployments with the `shipit.shopify.io/restart` annotation " \
      "and name=web,branch=staging selector",
      "Triggered `staging-web` restart",
      "Waiting for rollout",
      %r{Successfully restarted in \d+\.\ds: Deployment/staging-web},
      "Result: SUCCESS",
      "Successfully restarted 1 resource",
      %r{Deployment/staging-web.*1 availableReplica},
    ],
      in_order: true)

    assert(fetch_restarted_at("staging-web"), "RESTARTED_AT is present after the restart")
    refute(fetch_restarted_at("master-web"), "no RESTARTED_AT env on fresh deployment")
  end

  def test_restart_by_annotation_none_found
    restart = build_restart_task
    assert_restart_failure(restart.perform)
    assert_logs_match_all([
      "Configured to restart all deployments with the `shipit.shopify.io/restart` annotation",
      "Result: FAILURE",
      %r{No deployments with the `shipit\.shopify\.io/restart` annotation found in namespace},
    ],
      in_order: true)
  end

  def test_restart_named_deployments_twice
    assert_deploy_success(deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb"]))

    refute(fetch_restarted_at("web"), "no RESTARTED_AT env on fresh deployment")

    restart = build_restart_task
    assert_restart_success(restart.perform(%w(web)))

    assert_logs_match_all([
      "Configured to restart deployments by name: web",
      "Triggered `web` restart",
      "Waiting for rollout",
      %r{Successfully restarted in \d+\.\d+s: Deployment/web},
      "Result: SUCCESS",
      "Successfully restarted 1 resource",
      %r{Deployment/web.*1 availableReplica},
    ],
      in_order: true)

    first_restarted_at = fetch_restarted_at("web")
    assert(first_restarted_at, "RESTARTED_AT is present after first restart")

    Timecop.freeze(1.second.from_now) do
      assert_restart_success(restart.perform(%w(web)))
    end

    second_restarted_at = fetch_restarted_at("web")
    assert(second_restarted_at, "RESTARTED_AT is present after second restart")
    refute_equal(first_restarted_at.value, second_restarted_at.value)
  end

  def test_restart_with_same_resource_twice
    assert_deploy_success(deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb"]))

    refute(fetch_restarted_at("web"), "no RESTARTED_AT env on fresh deployment")

    restart = build_restart_task
    assert_restart_success(restart.perform(%w(web web)))

    assert_logs_match_all([
      "Configured to restart deployments by name: web",
      "Triggered `web` restart",
      "Result: SUCCESS",
      "Successfully restarted 1 resource",
      %r{Deployment/web.*1 availableReplica},
    ],
      in_order: true)

    assert(fetch_restarted_at("web"), "RESTARTED_AT is present after the restart")
  end

  def test_restart_not_existing_deployment
    restart = build_restart_task
    assert_restart_failure(restart.perform(%w(web)))
    assert_logs_match_all([
      "Configured to restart deployments by name: web",
      "Result: FAILURE",
      "Deployment `web` not found in namespace",
    ],
      in_order: true)
  end

  def test_restart_one_not_existing_deployment
    assert(deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb"]))

    restart = build_restart_task
    assert_restart_failure(restart.perform(%w(walrus web)))

    refute(fetch_restarted_at("web"), "no RESTARTED_AT env after failed restart task")
    assert_logs_match_all([
      "Configured to restart deployments by name: walrus, web",
      "Result: FAILURE",
      "Deployment `walrus` not found in namespace",
    ],
      in_order: true)
  end

  def test_restart_none
    restart = build_restart_task
    assert_restart_failure(restart.perform([]))
    assert_logs_match_all([
      "Result: FAILURE",
      "Configured to restart deployments by name, but list of names was blank",
    ],
      in_order: true)
  end

  def test_restart_deployments_and_selector
    restart = build_restart_task
    assert_restart_failure(restart.perform(%w(web), selector: KubernetesDeploy::LabelSelector.parse("app=web")))
    assert_logs_match_all([
      "Result: FAILURE",
      "Can't specify deployment names and selector at the same time",
    ],
      in_order: true)
  end

  def test_restart_not_existing_context
    restart = KubernetesDeploy::RestartTask.new(
      context: "walrus",
      namespace: @namespace,
      logger: logger
    )
    assert_restart_failure(restart.perform(%w(web)))
    assert_logs_match_all([
      "Result: FAILURE",
      /- Context walrus missing from your kubeconfig file\(s\)/,
    ],
      in_order: true)
  end

  def test_restart_not_existing_namespace
    restart = KubernetesDeploy::RestartTask.new(
      context: KubeclientHelper::TEST_CONTEXT,
      namespace: "walrus",
      logger: logger
    )
    assert_restart_failure(restart.perform(%w(web)))
    assert_logs_match_all([
      "Result: FAILURE",
      "- Could not find Namespace: walrus in Context: #{KubeclientHelper::TEST_CONTEXT}",
    ],
      in_order: true)
  end

  def test_restart_failure
    success = deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb"]) do |fixtures|
      deployment = fixtures["web.yml.erb"]["Deployment"].first
      deployment["spec"]["progressDeadlineSeconds"] = 30
      container = deployment["spec"]["template"]["spec"]["containers"].first
      container["readinessProbe"] = {
        "failureThreshold" => 1,
        "periodSeconds" => 1,
        "initialDelaySeconds" => 0,
        "exec" => {
          "command" => [
            "/bin/sh",
            "-c",
            "test $(env | grep -s RESTARTED_AT -c) -eq 0",
          ],
        },
      }
    end
    assert_deploy_success(success)

    restart = build_restart_task
    assert_raises(KubernetesDeploy::DeploymentTimeoutError) { restart.perform!(%w(web)) }

    assert_logs_match_all([
      "Triggered `web` restart",
      "Deployment/web rollout timed out",
      "Result: TIMED OUT",
      "Timed out waiting for 1 resource to restart",
      "Deployment/web: TIMED OUT",
      "The following containers have not passed their readiness probes",
      "app must exit 0 from the following command",
      "Final status: 2 replicas, 1 updatedReplica, 1 availableReplica, 1 unavailableReplica",
      "Unhealthy: Readiness probe failed",
    ],
      in_order: true)
  end

  def test_restart_successful_with_partial_availability
    result = deploy_fixtures("slow-cloud") do |fixtures|
      web = fixtures["web.yml.erb"]["Deployment"].first
      web["spec"]["strategy"]['rollingUpdate']['maxUnavailable'] = '50%'
      container = web["spec"]["template"]["spec"]["containers"].first
      container["readinessProbe"] = {
        "exec" => { "command" => %w(sleep 5) },
        "timeoutSeconds" => 6,
      }
    end
    assert_deploy_success(result)

    restart = build_restart_task
    assert_restart_success(restart.perform(%w(web)))

    pods = kubeclient.get_pods(namespace: @namespace, label_selector: 'name=web,app=slow-cloud')
    new_pods = pods.select do |pod|
      pod.spec.containers.any? { |c| c["name"] == "app" && c.env&.find { |n| n.name == "RESTARTED_AT" } }
    end
    assert(new_pods.length >= 1, "Expected at least one new pod, saw #{new_pods.length}")

    new_ready_pods = new_pods.select do |pod|
      pod.status.phase == "Running" &&
      pod.status.conditions.any? { |condition| condition["type"] == "Ready" && condition["status"] == "True" }
    end
    assert_equal(1, new_ready_pods.length, "Expected exactly one new pod to be ready, saw #{new_ready_pods.length}")

    assert(fetch_restarted_at("web"), "RESTARTED_AT is present after the restart")
  end

  def test_verify_result_false_succeeds
    assert_deploy_success(deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb", "redis.yml"]))

    refute(fetch_restarted_at("web"), "no RESTARTED_AT env on fresh deployment")
    refute(fetch_restarted_at("redis"), "no RESTARTED_AT env on fresh deployment")

    restart = build_restart_task
    assert_restart_success(restart.perform(verify_result: false))

    assert_logs_match_all([
      "Configured to restart all deployments with the `shipit.shopify.io/restart` annotation",
      "Triggered `web` restart",
      "Result: SUCCESS",
      "Result verification is disabled for this task",
    ],
      in_order: true)

    assert(fetch_restarted_at("web"), "RESTARTED_AT is present after the restart")
    refute(fetch_restarted_at("redis"), "no RESTARTED_AT env on fresh deployment")
  end

  def test_verify_result_false_fails_on_config_checks
    restart = build_restart_task
    assert_restart_failure(restart.perform(verify_result: false))
    assert_logs_match_all([
      "Configured to restart all deployments with the `shipit.shopify.io/restart` annotation",
      "Result: FAILURE",
      %r{No deployments with the `shipit\.shopify\.io/restart` annotation found in namespace},
    ],
      in_order: true)
  end

  def test_verify_result_false_succeeds_quickly_when_verification_would_timeout
    success = deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb"]) do |fixtures|
      deployment = fixtures["web.yml.erb"]["Deployment"].first
      deployment["spec"]["progressDeadlineSeconds"] = 30
      container = deployment["spec"]["template"]["spec"]["containers"].first
      container["readinessProbe"] = {
        "failureThreshold" => 1,
        "periodSeconds" => 1,
        "initialDelaySeconds" => 0,
        "exec" => {
          "command" => [
            "/bin/sh",
            "-c",
            "test $(env | grep -s RESTARTED_AT -c) -eq 0",
          ],
        },
      }
    end
    assert_deploy_success(success)

    restart = build_restart_task
    restart.perform!(%w(web), verify_result: false)

    assert_logs_match_all([
      "Triggered `web` restart",
      "Result: SUCCESS",
      "Result verification is disabled for this task",
    ],
      in_order: true)
  end

  private

  def build_restart_task
    KubernetesDeploy::RestartTask.new(
      context: KubeclientHelper::TEST_CONTEXT,
      namespace: @namespace,
      logger: logger
    )
  end

  def fetch_restarted_at(deployment_name)
    deployment = v1beta1_kubeclient.get_deployment(deployment_name, @namespace)
    containers = deployment.spec.template.spec.containers
    app_container = containers.find { |c| c["name"] == "app" }
    app_container&.env&.find { |n| n.name == "RESTARTED_AT" }
  end
end
