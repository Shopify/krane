require 'test_helper'

class KubernetesDeployTest < Minitest::Test
  def setup
    @logger_stream = StringIO.new
    @logger = Logger.new(@logger_stream)
    KubernetesDeploy.logger = @logger
  end

  def teardown
    @logger_stream.close
  end

  def test_that_it_has_a_version_number
    refute_nil ::KubernetesDeploy::VERSION
  end

  def test_basic
    runner = KubernetesDeploy::Runner.new(
      namespace: "trashbin",
      current_sha: "abcabcabc",
      context: "minikube",
      template_dir: File.expand_path("./test/fixtures/trashbin"),
      wait_for_completion: true,
    )
    runner.run

    pods = kubeclient.get_pods
    assert_equal 3, pods.size

    speaker_pods, rest_pods = pods.partition { |p| p.metadata.name =~ /speaker-pod/ }
    assert_equal 2, rest_pods.size
    assert_equal 1, speaker_pods.size

    statuses = rest_pods.map { |pod| pod.status.phase }
    assert statuses.all? { |p| p == "Running" }, "Pod statuses have to be Running, got: #{statuses.inspect}"
  end

  def test_initializer
    runner = KubernetesDeploy::Runner.new(
      namespace: "",
      current_sha: "",
      context: "",
      template_dir: "unknown",
      wait_for_completion: true,
    )
    error = assert_raises(KubernetesDeploy::FatalDeploymentError) do
      runner.run
    end

    assert_includes error.to_s, "Kube config not found at /home/"
    assert_includes error.to_s, "Current SHA must be specified"
    assert_includes error.to_s, "Namespace must be specified"
    assert_includes error.to_s, "Context must be specified"
    assert_match /Template path (\S+) doesn't exist/, error.to_s
  end
end
