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
      environment: "production",
      current_sha: "abcabcabc",
      context: "chi2",
      kubeconfig_path: File.expand_path("./test/fixtures/kubeconfig.yml"),
      template_dir: File.expand_path("./test/fixtures/trashbin"),
    )
    # it works, but running this would break things that are running in chi2
    # runner.run
  end


  def test_validates
    runner = KubernetesDeploy::Runner.new(
      namespace: "",
      environment: "",
      current_sha: "",
      context: "",
      kubeconfig_path: "/home/",
      template_dir: "unknown",
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
