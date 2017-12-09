# frozen_string_literal: true
require 'test_helper'

class DeployTaskTest < KubernetesDeploy::TestCase
  def test_that_it_has_a_version_number
    refute_nil ::KubernetesDeploy::VERSION
  end

  def test_error_message_when_kubeconfig_not_set
    runner_with_env(nil)
    assert_logs_match("Configuration invalid")
    assert_logs_match("$KUBECONFIG not set")
    assert_logs_match("Current SHA must be specified")
    assert_logs_match("Namespace must be specified")
    assert_logs_match("Context must be specified")
    assert_logs_match(/Template directory (\S+) doesn't exist/)
  end

  def test_initializer
    runner_with_env("/this-really-should/not-exist")
    assert_logs_match("Configuration invalid")
    assert_logs_match("Kube config not found at /this-really-should/not-exist")
    assert_logs_match("Current SHA must be specified")
    assert_logs_match("Namespace must be specified")
    assert_logs_match("Context must be specified")
    assert_logs_match(/Template directory (\S+) doesn't exist/)
  end

  private

  def runner_with_env(value)
    # TODO: Switch to --kubeconfig for kubectl shell out and pass env var as arg to DeployTask init
    # Then fix this crappy env manipulation
    original_env = ENV["KUBECONFIG"]
    ENV["KUBECONFIG"] = value

    deploy = KubernetesDeploy::DeployTask.new(
      namespace: "",
      context: "",
      logger: logger,
      current_sha: "",
      template_dir: "unknown",
    )
    deploy.run
  ensure
    ENV["KUBECONFIG"] = original_env
  end
end
