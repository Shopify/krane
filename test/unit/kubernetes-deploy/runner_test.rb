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
      logger: logger,
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

  def test_template_variables
    runner = KubernetesDeploy::Runner.new(
      namespace: "mynamespace",
      context: "mycontext",
      logger: logger,
      current_sha: "somesha",
      template_dir: "unknown",
    )

    variables = runner.template_variables
    assert_equal "mycontext", variables["context"]
    assert_equal "mynamespace", variables["namespace"]
    assert_equal "somesha", variables["current_sha"]
  end
end
