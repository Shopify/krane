# frozen_string_literal: true
require 'test_helper'

class RunnerTest < KubernetesDeploy::TestCase
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
      context: "",
      logger: test_logger,
      current_sha: "",
      template_dir: "unknown",
    )
    runner.run

    assert_logs_match("Configuration invalid")
    assert_logs_match("Kube config not found at /this-really-should/not-exist")
    assert_logs_match("Current SHA must be specified")
    assert_logs_match("Namespace must be specified")
    assert_logs_match("Context must be specified")
    assert_logs_match(/Template directory (\S+) doesn't exist/)

  ensure
    ENV["KUBECONFIG"] = original_env
  end
end
