# frozen_string_literal: true
require 'integration_test_helper'

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

  # Run statsd tests in serial because capture_statsd_calls modifies global state in a way
  # that makes capturing metrics across parrallel runs unreliable
  def test_failure_statsd_metric_emitted
    bad_ns = "missing"
    task_runner = build_task_runner(ns: bad_ns)

    result = false
    metrics = capture_statsd_calls do
      result = task_runner.run(run_params)
    end

    assert_task_run_failure(result)

    metric = metrics.detect { |m| m.tags.include? "namespace:#{bad_ns}" }
    assert metric, "No metrics found for this test"
    metric_tags = metric.tags
    assert_includes metric_tags, "context:#{KubeclientHelper::TEST_CONTEXT}"
    assert_includes metric_tags, "status:failure"
  end

  def test_success_statsd_metric_emitted
    deploy_task_template
    task_runner = build_task_runner

    result = false
    metrics = capture_statsd_calls do
      result = task_runner.run(run_params.merge(verify_result: false))
    end

    assert_task_run_success(result)

    metric = metrics.detect { |m| m.tags.include? "namespace:#{@namespace}" }
    assert metric, "No metrics found for this test"
    metric_tags = metric.tags
    assert_includes metric_tags, "context:#{KubeclientHelper::TEST_CONTEXT}"
    assert_includes metric_tags, "status:success"
  end

  def test_timedout_statsd_metric_emitted
    deploy_task_template
    task_runner = build_task_runner(max_watch_seconds: 0)

    result = false
    metrics = capture_statsd_calls do
      result = task_runner.run(run_params.merge(args: ["sleep 5"]))
    end

    assert_task_run_failure(result, :timed_out)

    metric = metrics.detect { |m| m.tags.include? "namespace:#{@namespace}" }
    assert metric, "No metrics found for this test"
    metric_tags = metric.tags
    assert_includes metric_tags, "context:#{KubeclientHelper::TEST_CONTEXT}"
    assert_includes metric_tags, "status:timeout"
  end
end
