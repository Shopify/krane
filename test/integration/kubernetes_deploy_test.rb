require 'test_helper'

class KubernetesDeployTest < KubernetesDeploy::IntegrationTest
  def test_basic
    runner = KubernetesDeploy::Runner.new(
      namespace: @namespace,
      current_sha: "abcabcabc",
      context: "minikube",
      template_dir: File.expand_path("./test/fixtures/basic"),
      wait_for_completion: true,
    )
    runner.run

    pods = kubeclient.get_pods(namespace: @namespace)
    managed_pods, unmanaged_pods = pods.partition do |pod|
      pod.metadata.ownerReferences && pod.metadata.ownerReferences.first.kind == "ReplicaSet"
    end

    assert_equal 2, managed_pods.size
    managed_pods.each do |pod|
      assert_equal "Running", pod.status.phase
    end

    assert_equal 1, unmanaged_pods.size
    assert_equal "Succeeded", unmanaged_pods.first.status.phase
  end
end
