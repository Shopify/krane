# frozen_string_literal: true
require 'test_helper'

class GlobalDeployTaskTest < Krane::TestCase
  def test_kubeconfig_configured_correctly
    task = Krane::GlobalDeployTask.new(
      context: KubeclientHelper::TEST_CONTEXT,
      logger: logger,
      filenames: ["unknown"],
      kubeconfig: '/some/path.yml',
    )
    assert_equal('/some/path.yml', task.task_config.kubeconfig)
    refute_nil(task.kubeclient_builder, "Expected kubeclient builder.")
  end
end
