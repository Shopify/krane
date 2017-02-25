module FixtureSetAssertions
  class Basic < FixtureSet
    def initialize(namespace)
      @namespace = namespace
      @app_name = "basic"
    end

    def assert_all_up
      assert_unmanaged_pod_statuses("Succeeded")
      assert_all_web_resources_up
      assert_all_redis_resources_up
      assert_configmap_data_present
    end

    def assert_unmanaged_pod_statuses(status, count=1)
      pods = kubeclient.get_pods(namespace: namespace, label_selector: "type=unmanaged-pod,app=#{app_name}")
      assert_equal count, pods.size, "Expected to find #{count} unmanaged pod(s), found #{pods.size}"
      assert pods.all? { |pod| pod.status.phase == status }
    end

    def refute_managed_pod_exists
      pods = kubeclient.get_pods(namespace: namespace, label_selector: "type=unmanaged-pod,app=#{app_name}")
      assert_equal 0, pods.size, "Expected to find 0 managed pods, found #{pods.size}"
    end

    def assert_configmap_data_present
      assert_configmap_present("basic-configmap-data", { datapoint1: "value1", datapoint2: "value2" })
    end

    def refute_configmap_data_exists
      refute_resource_exists("config_map", "basic-configmap-data")
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
  end
end
