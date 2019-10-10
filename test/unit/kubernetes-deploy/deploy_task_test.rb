# frozen_string_literal: true
require 'test_helper'

class DeployTaskTest < KubernetesDeploy::TestCase
  include EnvTestHelper

  def test_that_it_has_a_version_number
    refute_nil(::KubernetesDeploy::VERSION)
  end

  def test_initializer_without_valid_file
    KubernetesDeploy::Kubectl.any_instance.expects(:run).at_least_once.returns(["", "", SystemExit.new(0)])
    KubernetesDeploy::Kubectl.any_instance.expects(:server_version).at_least_once.returns(
      Gem::Version.new(KubernetesDeploy::MIN_KUBE_VERSION)
    )
    KubernetesDeploy::DeployTask.new(
      namespace: "something",
      context: KubeclientHelper::TEST_CONTEXT,
      logger: logger,
      current_sha: "",
      template_paths: ["unknown"],
    ).run
    assert_logs_match("Configuration invalid")
    assert_logs_match(/File (\S+) does not exist/)
  end
end
