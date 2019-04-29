# frozen_string_literal: true
module FixtureSetAssertions
  class HelloCloud < FixtureSet
    def initialize(namespace)
      @namespace = namespace
      @app_name = "hello-cloud"
    end

    def assert_all_up
      assert_unmanaged_pod_statuses("Succeeded")
      assert_all_web_resources_up
      assert_all_redis_resources_up
      assert_configmap_data_present
      assert_podtemplate_runner_present
      assert_poddisruptionbudget
      assert_bare_replicaset_up
      assert_all_service_accounts_up
      assert_all_roles_up
      assert_all_role_bindings_up
      assert_daemon_set_up
      assert_stateful_set_up
      assert_job_up
      assert_network_policy_up
      assert_secret_created
    end

    def assert_unmanaged_pod_statuses(status, count = 2)
      pods = kubeclient.get_pods(namespace: namespace, label_selector: "type=unmanaged-pod,app=#{app_name}")
      assert_equal(count, pods.count { |pod| pod.status.phase == status })
    end

    def refute_unmanaged_pod_exists
      pods = kubeclient.get_pods(namespace: namespace, label_selector: "type=unmanaged-pod,app=#{app_name}")
      assert_equal(0, pods.size, "Expected to find 0 unmanaged pods, found #{pods.size}")
    end

    def assert_configmap_data_present
      assert_configmap_present("hello-cloud-configmap-data", datapoint1: "value1", datapoint2: "value2")
    end

    def refute_configmap_data_exists
      refute_resource_exists("config_map", "hello-cloud-configmap-data")
    end

    def assert_all_web_resources_up
      assert_pod_status("web", "Running")
      assert_ingress_up("web")
      assert_service_up("web")
      assert_deployment_up("web", replicas: 1)
    end

    def refute_web_resources_exist
      refute_resource_exists("deployment", "web", beta: true)
      refute_resource_exists("ingress", "web", beta: true)
      refute_resource_exists("service", "web")
    end

    def assert_all_redis_resources_up
      assert_pod_status("redis", "Running")
      assert_service_up("redis")
      assert_deployment_up("redis", replicas: 1)
      assert_pvc_status("redis", "Bound")
    end

    def refute_redis_resources_exist(expect_pvc: false)
      refute_resource_exists("deployment", "redis", beta: true)
      refute_resource_exists("service", "redis")
      if expect_pvc
        assert_pvc_status("redis", "Bound")
      else
        refute_resource_exists("pvc", "redis")
      end
    end

    def assert_podtemplate_runner_present
      assert_pod_templates_present("hello-cloud-template-runner")
    end

    def assert_poddisruptionbudget
      budgets = policy_v1beta1_kubeclient.get_pod_disruption_budgets(namespace: namespace)
      assert_equal(1, budgets.size, "Expected 1 PodDisruptionBudget")
      assert_equal(2, budgets[0].spec.minAvailable, "Unexpected value in PodDisruptionBudget spec")
    end

    def assert_bare_replicaset_up
      assert_pod_status("bare-replica-set", "Running")
      assert(assert_replica_set_up("bare-replica-set", replicas: 1))
    end

    def assert_all_service_accounts_up
      assert_service_account_present("build-robot")
    end

    def assert_all_roles_up
      assert_role_present("role")
    end

    def assert_all_role_bindings_up
      assert_role_binding_present("role-binding")
    end

    def assert_daemon_set_up
      assert_daemon_set_present("ds-app")
    end

    def assert_stateful_set_up
      assert_stateful_set_present("stateful-busybox")
    end

    def assert_job_up
      assert_job_exists("hello-job")
    end

    def assert_network_policy_up
      assert_network_policy_present("allow-all-network-policy")
    end

    def assert_secret_created
      assert_secret_present("hello-secret")
    end
  end
end
