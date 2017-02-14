require 'test_helper'

class RunnerTest < Minitest::Test
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

  def test_initializer
    # TODO: Switch to --kubeconfig for kubectl shell out and pass env var as arg to Runner init
    # Then fix this crappy env manipulation
    original_env = ENV["KUBECONFIG"]
    ENV["KUBECONFIG"] = "/this-really-should/not-exist"

    runner = KubernetesDeploy::Runner.new(
      namespace: "",
      current_sha: "",
      context: "",
      template_dir: "unknown",
      wait_for_completion: true,
    )
    error_msg = assert_raises(KubernetesDeploy::FatalDeploymentError) do
      runner.run
    end.to_s

    assert_includes error_msg, "Kube config not found at /this-really-should/not-exist"
    assert_includes error_msg, "Current SHA must be specified"
    assert_includes error_msg, "Namespace must be specified"
    assert_includes error_msg, "Context must be specified"
    assert_match /Template directory (\S+) doesn't exist/, error_msg

    ENV["KUBECONFIG"] = original_env
  end
end
