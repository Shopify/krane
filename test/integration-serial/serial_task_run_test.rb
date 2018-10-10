# frozen_string_literal: true
require 'test_helper'

class SerialTaskRunTest < KubernetesDeploy::IntegrationTest
  include TaskRunnerTestHelper

  # Mocha is not thread-safe: https://github.com/freerange/mocha#thread-safety
  def test_run_without_verify_result_fails_if_pod_was_not_created
    deploy_task_template
    task_runner = build_task_runner

    # Sketchy, but stubbing the kubeclient doesn't work (and wouldn't be concurrency-friendly)
    # Finding a way to reliably trigger a create failure would be much better, if possible
    mock = mock()
    mock.expects(:get_namespace)
    template = kubeclient.get_pod_template('hello-cloud-template-runner', @namespace)
    mock.expects(:get_pod_template).returns(template)
    mock.expects(:create_pod).raises(Kubeclient::HttpError.new("409", "Pod with same name exists", {}))
    task_runner.instance_variable_set(:@kubeclient, mock)

    result = task_runner.run(run_params(verify_result: false))
    assert_task_run_failure(result)

    assert_logs_match_all([
      "Running pod",
      "Result: FAILURE",
      "Failed to create pod",
      "Kubeclient::HttpError: Pod with same name exists"
    ], in_order: true)
  end
end
