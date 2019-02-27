# frozen_string_literal: true
require 'test_helper'

class DeployTaskTest < KubernetesDeploy::TestCase
  include EnvTestHelper

  def test_that_it_has_a_version_number
    refute_nil(::KubernetesDeploy::VERSION)
  end

  def test_initializer
    runner_with_kubeconfig("/this-really-should/not-exist")
    assert_logs_match("Configuration invalid")
    assert_logs_match("Kube config not found at /this-really-should/not-exist")
    assert_logs_match("Namespace must be specified")
    assert_logs_match("Context must be specified")
    assert_logs_match(/Template directory (\S+) doesn't exist/)
  end

  private

  def runner_with_kubeconfig(value)
    deploy = KubernetesDeploy::DeployTask.new(
      kubeconfig: value,
      namespace: "",
      context: "",
      logger: logger,
      current_sha: "",
      template_dir: "unknown",
    )
    deploy.run
  end
end
