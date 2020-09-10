# frozen_string_literal: true
require 'test_helper'

class RestartTaskTest < Krane::TestCase
  def test_kubeconfig_configured_correctly
    task = Krane::RestartTask.new(
      namespace: "something",
      context: KubeclientHelper::TEST_CONTEXT,
      logger: logger,
      kubeconfig: '/some/path.yml',
    )
    assert_equal('/some/path.yml', task.task_config.kubeconfig)
    assert_equal(['/some/path.yml'], task.send(:kubeclient_builder).kubeconfig_files)
  end
end
