# frozen_string_literal: true
require 'integration_test_helper'
require 'krane/restart_task'

class RestartTaskTest < Krane::IntegrationTest
  def test_restart_by_annotation
    assert_deploy_success(deploy_fixtures("hello-cloud",
      subset: ["configmap-data.yml", "web.yml.erb", "redis.yml", "stateful_set.yml", "daemon_set.yml"],
      render_erb: true))

    refute(fetch_restarted_at("web"), "no restart annotation on fresh deployment")
    refute(fetch_restarted_at("stateful-busybox", kind: :statefulset), "no restart annotation on fresh stateful set")
    refute(fetch_restarted_at("ds-app", kind: :daemonset), "no restart annotation on fresh daemon set")
    refute(fetch_restarted_at("redis"), "no restart annotation on fresh deployment")

    restart = build_restart_task
    assert_restart_success(restart.perform)

    assert_logs_match_all([
      "Configured to restart all workloads with the `shipit.shopify.io/restart` annotation",
      "Triggered `Deployment/web` restart",
      "Waiting for rollout",
      %r{Successfully restarted in \d+\.\d+s: Deployment/web},
      "Result: SUCCESS",
      "Successfully restarted 3 resources",
      %r{Deployment/web.*1 availableReplica},
    ],
      in_order: true)

    assert(fetch_restarted_at("web"), "restart annotation is present after the restart")
    assert(fetch_restarted_at("stateful-busybox", kind: :statefulset), "no restart annotation on fresh stateful set")
    assert(fetch_restarted_at("ds-app", kind: :daemonset), "no restart annotation on fresh daemon set")
    refute(fetch_restarted_at("redis"), "no restart annotation env on fresh deployment")
  end

  def test_restart_by_selector
    assert_deploy_success(deploy_fixtures("branched",
      bindings: { "branch" => "master" },
      selector: Krane::LabelSelector.parse("branch=master"),
      render_erb: true))
    assert_deploy_success(deploy_fixtures("branched",
      bindings: { "branch" => "staging" },
      selector: Krane::LabelSelector.parse("branch=staging"),
      render_erb: true))

    refute(fetch_restarted_at("master-web"), "no restart annotation on fresh deployment")
    refute(fetch_restarted_at("staging-web"), "no restart annotation on fresh deployment")
    refute(fetch_restarted_at("master-stateful-busybox", kind: :statefulset),
      "no restart annotation on fresh stateful set")
    refute(fetch_restarted_at("staging-stateful-busybox", kind: :statefulset),
      "no restart annotation on fresh stateful set")
    refute(fetch_restarted_at("master-ds-app", kind: :daemonset), "no restart annotation on fresh daemon set")
    refute(fetch_restarted_at("staging-ds-app", kind: :daemonset), "no restart annotation on fresh daemon set")

    restart = build_restart_task
    assert_restart_success(restart.perform(selector: Krane::LabelSelector.parse("branch=staging")))

    assert_logs_match_all([
      "Configured to restart all workloads with the `shipit.shopify.io/restart` annotation " \
      "and branch=staging selector",
      "Triggered `Deployment/staging-web` restart",
      "Triggered `StatefulSet/staging-stateful-busybox` restart",
      "Triggered `DaemonSet/staging-ds-app` restart",
      "Waiting for rollout",
      %r{Successfully restarted in \d+\.\ds: Deployment/staging-web},
      "Result: SUCCESS",
      "Successfully restarted 3 resources",
      %r{Deployment/staging-web.*1 availableReplica},
    ],
      in_order: true)

    assert(fetch_restarted_at("staging-web"), "restart annotation is present after the restart")
    refute(fetch_restarted_at("master-web"), "no restart annotation on fresh deployment")
    assert(fetch_restarted_at("staging-stateful-busybox", kind: :statefulset),
      "restart annotation is present after the restart")
    refute(fetch_restarted_at("master-stateful-busybox", kind: :statefulset),
      "no restart annotation on fresh stateful set")
    assert(fetch_restarted_at("staging-ds-app", kind: :daemonset), "restart annotation is present after the restart")
    refute(fetch_restarted_at("master-ds-app", kind: :daemonset), "no restart annotation on fresh daemon set")
  end

  def test_restart_by_annotation_none_found
    restart = build_restart_task
    assert_restart_failure(restart.perform)
    assert_logs_match_all([
      "Configured to restart all workloads with the `shipit.shopify.io/restart` annotation",
      "Result: FAILURE",
      %r{No deployments, statefulsets, or daemonsets, with the `shipit\.shopify\.io/restart` annotation found},
    ],
      in_order: true)
  end

  def test_restart_named_workloads_twice
    assert_deploy_success(deploy_fixtures("hello-cloud",
      subset: ["configmap-data.yml", "web.yml.erb", "stateful_set.yml", "daemon_set.yml"],
      render_erb: true))

    refute(fetch_restarted_at("web"), "no restart annotation on fresh deployment")

    restart = build_restart_task
    assert_restart_success(
      restart.perform(deployments: %w(web), statefulsets: %w(stateful-busybox), daemonsets: %w(ds-app))
    )

    assert_logs_match_all([
      "Configured to restart deployments by name: web",
      "Configured to restart statefulsets by name: stateful-busybox",
      "Configured to restart daemonsets by name: ds-app",
      "Triggered `Deployment/web` restart",
      "Triggered `StatefulSet/stateful-busybox` restart",
      "Triggered `DaemonSet/ds-app` restart",
      "Waiting for rollout",
      %r{Successfully restarted in \d+\.\d+s: Deployment/web},
      "Result: SUCCESS",
      "Successfully restarted 3 resources",
      %r{Deployment/web.*1 availableReplica},
    ],
      in_order: true)

    first_restarted_at_deploy = fetch_restarted_at("web")
    first_restarted_at_statefulset = fetch_restarted_at("stateful-busybox", kind: :statefulset)
    first_restarted_at_daemonset = fetch_restarted_at("ds-app", kind: :daemonset)
    assert(first_restarted_at_deploy, "restart annotation is present after first restart")
    assert(first_restarted_at_statefulset, "restart annotation is present after first restart")
    assert(first_restarted_at_daemonset, "restart annotation is present after first restart")

    Timecop.freeze(1.second.from_now) do
      assert_restart_success(
        restart.perform(deployments: %w(web), statefulsets: %w(stateful-busybox), daemonsets: %w(ds-app))
      )
    end

    second_restarted_at_deploy = fetch_restarted_at("web")
    second_restarted_at_statefulset = fetch_restarted_at("stateful-busybox", kind: :statefulset)
    second_restarted_at_daemonset = fetch_restarted_at("ds-app", kind: :daemonset)
    assert(second_restarted_at_deploy, "restart annotation is present after second restart")
    assert(second_restarted_at_statefulset, "restart annotation is present after second restart")
    assert(second_restarted_at_daemonset, "restart annotation is present after second restart")
    refute_equal(first_restarted_at_deploy, second_restarted_at_deploy)
    refute_equal(first_restarted_at_statefulset, second_restarted_at_statefulset)
    refute_equal(first_restarted_at_daemonset, second_restarted_at_daemonset)
  end

  def test_restart_with_same_resource_twice
    assert_deploy_success(deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb"],
      render_erb: true))

    refute(fetch_restarted_at("web"), "no restart annotation on fresh deployment")

    restart = build_restart_task
    assert_restart_success(restart.perform(deployments: %w(web web)))

    assert_logs_match_all([
      "Configured to restart deployments by name: web",
      "Configured to restart statefulsets by name: stateful-busybox",
      "Configured to restart daemonsets by name: ds-app",
      "Triggered `Deployment/web` restart",
      "Triggered `StatefulSet/stateful-busybox` restart",
      "Triggered `DaemonSet/ds-app` restart",
      "Result: SUCCESS",
      "Successfully restarted 3 resources",
      %r{Deployment/web.*1 availableReplica},
    ],
      in_order: true)

    assert(fetch_restarted_at("web"), "restart annotation is present after the restart")
  end

  def test_restart_not_existing_deployment
    restart = build_restart_task
    assert_restart_failure(restart.perform(deployments: %w(web)))
    assert_logs_match_all([
      "Configured to restart deployments by name: web",
      "Result: FAILURE",
      "Deployment `web` not found in namespace",
    ],
      in_order: true)
  end

  def test_restart_one_not_existing_deployment
    assert(deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb"], render_erb: true))

    restart = build_restart_task
    assert_restart_failure(restart.perform(deployments: %w(walrus web)))

    refute(fetch_restarted_at("web"), "no restart annotation after failed restart task")
    assert_logs_match_all([
      "Configured to restart deployments by name: walrus, web",
      "Result: FAILURE",
      "Deployment `walrus` not found in namespace",
    ],
      in_order: true)
  end

  def test_restart_deployments_and_selector
    restart = build_restart_task
    assert_restart_failure(restart.perform(deployments: %w(web), selector: Krane::LabelSelector.parse("app=web")))
    assert_logs_match_all([
      "Result: FAILURE",
      "Can't specify workload names and selector at the same time",
    ],
      in_order: true)
  end

  def test_restart_not_existing_context
    restart = Krane::RestartTask.new(
      context: "walrus",
      namespace: @namespace,
      logger: logger
    )
    assert_restart_failure(restart.perform(deployments: %w(web)))
    assert_logs_match_all([
      "Result: FAILURE",
      /- Context walrus missing from your kubeconfig file\(s\)/,
    ],
      in_order: true)
  end

  def test_restart_not_existing_namespace
    restart = Krane::RestartTask.new(
      context: KubeclientHelper::TEST_CONTEXT,
      namespace: "walrus",
      logger: logger
    )
    assert_restart_failure(restart.perform(deployments: %w(web)))
    assert_logs_match_all([
      "Result: FAILURE",
      "- Could not find Namespace: walrus in Context: #{KubeclientHelper::TEST_CONTEXT}",
    ],
      in_order: true)
  end

  def test_restart_failure
    success = deploy_fixtures("downward_api", subset: ["configmap-data.yml", "web.yml.erb"],
      render_erb: true) do |fixtures|
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
            "test $(cat /etc/podinfo/annotations | grep -s kubectl.kubernetes.io/restartedAt -c) -eq 0",
          ],
        },
      }
    end
    assert_deploy_success(success)

    restart = build_restart_task
    assert_raises(Krane::DeploymentTimeoutError) { restart.perform!(deployments: %w(web)) }

    assert_logs_match_all([
      "Triggered `Deployment/web` restart",
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
    result = deploy_fixtures("slow-cloud", subset: %w(web-deploy-1.yml)) do |fixtures|
      web = fixtures["web-deploy-1.yml"]["Deployment"].first
      web["spec"]["strategy"]['rollingUpdate']['maxUnavailable'] = '50%'
      container = web["spec"]["template"]["spec"]["containers"].first
      container["readinessProbe"] = {
        "exec" => { "command" => %w(sleep 5) },
        "timeoutSeconds" => 6,
      }
    end
    assert_deploy_success(result)

    restart = build_restart_task
    assert_restart_success(restart.perform(deployments: %w(web)))

    pods = kubeclient.get_pods(namespace: @namespace, label_selector: 'name=web,app=slow-cloud')
    new_pods = pods.select do |pod|
      pod.metadata.annotations&.dig(Krane::RestartTask::RESTART_TRIGGER_ANNOTATION)
    end
    assert(new_pods.length >= 1, "Expected at least one new pod, saw #{new_pods.length}")

    new_ready_pods = new_pods.select do |pod|
      pod.status.phase == "Running" &&
      pod.status.conditions.any? { |condition| condition["type"] == "Ready" && condition["status"] == "True" }
    end
    assert_equal(1, new_ready_pods.length, "Expected exactly one new pod to be ready, saw #{new_ready_pods.length}")

    assert(fetch_restarted_at("web"), "restart annotation is present after the restart")
  end

  def test_verify_result_false_succeeds
    assert_deploy_success(deploy_fixtures("hello-cloud", subset: ["configmap-data.yml", "web.yml.erb", "redis.yml"],
      render_erb: true))

    refute(fetch_restarted_at("web"), "no restart annotation on fresh deployment")
    refute(fetch_restarted_at("redis"), "no restart annotation on fresh deployment")

    restart = build_restart_task
    assert_restart_success(restart.perform(verify_result: false))

    assert_logs_match_all([
      "Configured to restart all workloads with the `shipit.shopify.io/restart` annotation",
      "Triggered `Deployment/web` restart",
      "Result: SUCCESS",
      "Result verification is disabled for this task",
    ],
      in_order: true)

    assert(fetch_restarted_at("web"), "restart annotation is present after the restart")
    refute(fetch_restarted_at("redis"), "no restart annotation on fresh deployment")
  end

  def test_verify_result_false_fails_on_config_checks
    restart = build_restart_task
    assert_restart_failure(restart.perform(verify_result: false))
    assert_logs_match_all([
      "Configured to restart all workloads with the `shipit.shopify.io/restart` annotation",
      "Result: FAILURE",
      %r{No deployments, statefulsets, or daemonsets, with the `shipit\.shopify\.io/restart` annotation found},
    ],
      in_order: true)
  end

  def test_verify_result_false_succeeds_quickly_when_verification_would_timeout
    success = deploy_fixtures("hello-cloud",
      subset: ["configmap-data.yml", "web.yml.erb", "daemon_set.yml", "stateful_set.yml"],
      render_erb: true) do |fixtures|
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
            "test $(env | grep -s restart annotation -c) -eq 0",
          ],
        },
      }
    end
    assert_deploy_success(success)

    restart = build_restart_task
    restart.perform!(deployments: %w(web), statefulsets: %w(stateful-busybox), daemonsets: %w(ds-app),
      verify_result: false)

    assert_logs_match_all([
      "Triggered `Deployment/web` restart",
      "Triggered `StatefulSet/stateful-busybox` restart",
      "Triggered `DaemonSet/ds-app` restart",
      "Result: SUCCESS",
      "Result verification is disabled for this task",
    ],
      in_order: true)
  end

  private

  def build_restart_task
    Krane::RestartTask.new(
      context: KubeclientHelper::TEST_CONTEXT,
      namespace: @namespace,
      logger: logger
    )
  end

  def fetch_restarted_at(name, kind: :deployment)
    resource = case kind
    when :deployment
      apps_v1_kubeclient.get_deployment(name, @namespace)
    when :statefulset
      apps_v1_kubeclient.get_stateful_set(name, @namespace)
    when :daemonset
      apps_v1_kubeclient.get_daemon_set(name, @namespace)
    end
    resource.spec.template.metadata.annotations&.dig(Krane::RestartTask::RESTART_TRIGGER_ANNOTATION)
  end
end
