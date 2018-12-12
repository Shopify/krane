# frozen_string_literal: true

require 'test_helper'

class StatsDTest < KubernetesDeploy::TestCase
  include StatsDHelper
  class TestMeasureClass
    extend(KubernetesDeploy::StatsD::MeasureMethods)

    def thing_to_measure
      123
    end
    measure_method :thing_to_measure

    def measure_with_custom_metric; end
    measure_method :measure_with_custom_metric, "customized"

    def measured_method_raises
      raise ArgumentError
    end
    measure_method :measured_method_raises

    def statsd_tags
      { test: true }
    end
  end

  class TestMeasureNoTags
    extend(KubernetesDeploy::StatsD::MeasureMethods)
    def thing_to_measure; end
    measure_method :thing_to_measure
  end

  def test_build_when_statsd_addr_env_present_but_statsd_implementation_is_not
    original_addr = ENV['STATSD_ADDR']
    ENV['STATSD_ADDR'] = '127.0.0.1'
    original_impl = ENV['STATSD_IMPLEMENTATION']
    ENV['STATSD_IMPLEMENTATION'] = nil
    original_dev = ENV['STATSD_DEV']
    ENV['STATSD_DEV'] = nil

    KubernetesDeploy::StatsD.build

    assert_equal(:datadog, KubernetesDeploy::StatsD.backend.implementation)
  ensure
    ENV['STATSD_ADDR'] = original_addr
    ENV['STATSD_IMPLEMENTATION'] = original_impl
    ENV['STATSD_DEV'] = original_dev
    KubernetesDeploy::StatsD.build
  end

  def test_kubernetes_statsd_does_not_override_global_config
    old_prefix = ::StatsD.prefix
    old_sample_rate = ::StatsD.default_sample_rate

    ::StatsD.prefix = "test"
    ::StatsD.default_sample_rate = 2.0
    KubernetesDeploy::StatsD.build
    refute_equal(KubernetesDeploy::StatsD.prefix, ::StatsD.prefix)
    refute_equal(KubernetesDeploy::StatsD.default_sample_rate, ::StatsD.default_sample_rate)
    refute_equal(KubernetesDeploy::StatsD.backend, ::StatsD.backend)
  ensure
    ::StatsD.prefix = old_prefix
    ::StatsD.default_sample_rate = old_sample_rate
  end

  def test_measuring_non_existent_method_raises
    assert_raises_message(NotImplementedError, "Cannot instrument undefined method bogus_method") do
      TestMeasureClass.measure_method(:bogus_method)
    end
  end

  def test_measure_method_does_not_change_the_return_value
    assert_equal 123, TestMeasureClass.new.thing_to_measure
  end

  def test_measure_method_uses_expected_name_and_tags
    metrics = capture_statsd_calls do
      TestMeasureClass.new.thing_to_measure
    end
    assert_predicate metrics, :one?, "Expected 1 metric, got #{metrics.length}"
    assert_equal "KubernetesDeploy.thing_to_measure.duration", metrics.first.name
    assert_equal ["test:true"], metrics.first.tags
  end

  def test_measure_method_with_custom_metric_name
    metrics = capture_statsd_calls do
      TestMeasureClass.new.measure_with_custom_metric
    end
    assert_predicate metrics, :one?, "Expected 1 metric, got #{metrics.length}"
    assert_equal "KubernetesDeploy.customized", metrics.first.name
    assert_equal ["test:true"], metrics.first.tags
  end

  def test_measure_method_with_statsd_tags_undefined
    metrics = capture_statsd_calls do
      TestMeasureNoTags.new.thing_to_measure
    end
    assert_predicate metrics, :one?, "Expected 1 metric, got #{metrics.length}"
    assert_equal "KubernetesDeploy.thing_to_measure.duration", metrics.first.name
    assert_empty metrics.first.tags
  end

  def test_measure_method_that_raises_with_hash_tags
    metrics = capture_statsd_calls do
      tester = TestMeasureClass.new
      tester.expects(:statsd_tags).returns(test: true)
      assert_raises(ArgumentError) do
        tester.measured_method_raises
      end
    end
    assert_predicate metrics, :one?, "Expected 1 metric, got #{metrics.length}"
    assert_equal "KubernetesDeploy.measured_method_raises.duration", metrics.first.name
    assert_equal ["test:true", "error:true"], metrics.first.tags
  end

  def test_measure_method_that_raises_with_array_tags
    metrics = capture_statsd_calls do
      tester = TestMeasureClass.new
      tester.expects(:statsd_tags).returns(["test:true"])
      assert_raises(ArgumentError) do
        tester.measured_method_raises
      end
    end
    assert_predicate metrics, :one?, "Expected 1 metric, got #{metrics.length}"
    assert_equal "KubernetesDeploy.measured_method_raises.duration", metrics.first.name
    assert_equal ["test:true", "error:true"], metrics.first.tags
  end
end
