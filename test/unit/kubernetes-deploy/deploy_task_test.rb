# frozen_string_literal: true
require 'test_helper'

class DeployTaskTest < KubernetesDeploy::TestCase
  include EnvTestHelper

  def test_that_it_has_a_version_number
    refute_nil(::KubernetesDeploy::VERSION)
  end

  def test_initializer
    KubernetesDeploy::DeployTask.new(
      namespace: "",
      context: "",
      logger: logger,
      current_sha: "",
      template_paths: ["unknown"],
    ).run
    assert_logs_match("Configuration invalid")
    assert_logs_match("Namespace must be specified")
    assert_logs_match("Context must be specified")
    assert_logs_match(/File (\S+) does not exist/)
  end
end
