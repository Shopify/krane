# frozen_string_literal: true
require 'test_helper'

class RunnerTaskTest < Krane::TestCase
  def test_kubeconfig_configured_correctly
    task = Krane::RunnerTask.new(
      namespace: "something",
      context: KubeclientHelper::TEST_CONTEXT,
      logger: logger,
      kubeconfig: '/some/path.yml',
    )
    assert_equal('/some/path.yml', task.task_config.kubeconfig)
  end
end
