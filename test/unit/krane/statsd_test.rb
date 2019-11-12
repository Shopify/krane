# frozen_string_literal: true

require 'test_helper'

class StatsDTest < Krane::TestCase
  include StatsD::Instrument::Assertions

  class TestMeasureClass
    extend(Krane::StatsD::MeasureMethods)

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
    extend(Krane::StatsD::MeasureMethods)
    def thing_to_measure; end
    measure_method :thing_to_measure
  end

  def test_measuring_non_existent_method_raises
    assert_raises_message(NotImplementedError, "Cannot instrument undefined method bogus_method") do
      TestMeasureClass.measure_method(:bogus_method)
    end
  end

  def test_measure_method_does_not_change_the_return_value
    assert_equal(123, TestMeasureClass.new.thing_to_measure)
  end

  def test_measure_method_uses_expected_name_and_tags
    metrics = capture_statsd_calls(client: Krane::StatsD.client) do
      TestMeasureClass.new.thing_to_measure
    end
    assert_predicate(metrics, :one?, "Expected 1 metric, got #{metrics.length}")
    assert_equal("Krane.thing_to_measure.duration", metrics.first.name)
    assert_equal(["test:true"], metrics.first.tags)
  end

  def test_measure_method_with_custom_metric_name
    metrics = capture_statsd_calls(client: Krane::StatsD.client) do
      TestMeasureClass.new.measure_with_custom_metric
    end
    assert_predicate(metrics, :one?, "Expected 1 metric, got #{metrics.length}")
    assert_equal("Krane.customized", metrics.first.name)
    assert_equal(["test:true"], metrics.first.tags)
  end

  def test_measure_method_with_statsd_tags_undefined
    metrics = capture_statsd_calls(client: Krane::StatsD.client) do
      TestMeasureNoTags.new.thing_to_measure
    end
    assert_predicate(metrics, :one?, "Expected 1 metric, got #{metrics.length}")
    assert_equal("Krane.thing_to_measure.duration", metrics.first.name)
    assert_nil(metrics.first.tags)
  end

  def test_measure_method_that_raises_with_hash_tags
    metrics = capture_statsd_calls(client: Krane::StatsD.client) do
      tester = TestMeasureClass.new
      tester.expects(:statsd_tags).returns(test: true)
      assert_raises(ArgumentError) do
        tester.measured_method_raises
      end
    end
    assert_predicate(metrics, :one?, "Expected 1 metric, got #{metrics.length}")
    assert_equal("Krane.measured_method_raises.duration", metrics.first.name)
    assert_equal(["test:true", "error:true"], metrics.first.tags)
  end

  def test_measure_method_that_raises_with_array_tags
    metrics = capture_statsd_calls(client: Krane::StatsD.client) do
      tester = TestMeasureClass.new
      tester.expects(:statsd_tags).returns(["test:true"])
      assert_raises(ArgumentError) do
        tester.measured_method_raises
      end
    end
    assert_predicate(metrics, :one?, "Expected 1 metric, got #{metrics.length}")
    assert_equal("Krane.measured_method_raises.duration", metrics.first.name)
    assert_equal(["test:true", "error:true"], metrics.first.tags)
  end
end
