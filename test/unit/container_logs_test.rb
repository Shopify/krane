# frozen_string_literal: true
require 'test_helper'

class ContainerLogsTest < KubernetesDeploy::TestCase
  def setup
    super
    @logs = KubernetesDeploy::ContainerLogs.new(
      parent_id: 'pod/pod-123-456',
      container_name: 'A',
      logger: logger,
      namespace: 'test',
      context: KubeclientHelper::TEST_CONTEXT
    )
  end

  def test_sync_deduplicates_logs_emitted_fractional_seconds_apart
    KubernetesDeploy::Kubectl.any_instance.stubs(:run)
      .returns([logs_response_1, "", ""])
      .then.returns([logs_response_2, "", ""])
      .then.returns([logs_response_3, "", ""])
    @logs.sync
    @logs.sync
    @logs.sync

    assert_equal generate_log_messages(1..15), @logs.lines
  end

  def test_sync_handles_cycles_where_no_new_logs_available
    KubernetesDeploy::Kubectl.any_instance.stubs(:run)
      .returns([logs_response_1, "", ""])
      .then.returns(["", "", ""])
      .then.returns([logs_response_2, "", ""])
    @logs.sync
    @logs.sync
    @logs.sync

    assert_equal generate_log_messages(1..10), @logs.lines
  end

  def test_empty_delegated_to_lines
    KubernetesDeploy::Kubectl.any_instance.stubs(:run).returns([logs_response_1, "", ""])
    assert_predicate @logs, :empty?
    @logs.sync
    refute_predicate @logs, :empty?
  end

  def test_print_latest_and_print_all_output_the_correct_chunks
    KubernetesDeploy::Kubectl.any_instance.stubs(:run)
      .returns([logs_response_1, "", ""])
      .then.returns([logs_response_2, "", ""])

    @logs.sync
    @logs.print_latest
    assert_logs_match_all(generate_log_messages(1..3), in_order: true)

    reset_logger
    @logs.print_all
    assert_logs_match_all(generate_log_messages(1..3), in_order: true)

    reset_logger
    @logs.sync
    @logs.print_latest
    assert_logs_match_all(generate_log_messages(4..10), in_order: true)
    refute_logs_match("Line 3")

    reset_logger
    @logs.print_all
    assert_logs_match_all(generate_log_messages(1..10), in_order: true)
  end

  def test_print_latest_supports_prefixing
    KubernetesDeploy::Kubectl.any_instance.stubs(:run).returns([logs_response_1, "", ""])
    @logs.sync
    expected = [
      "[A]  Line 1",
      "[A]  Line 2",
      "[A]  Line 3"
    ]
    @logs.print_latest(prefix: true)
    assert_logs_match_all(expected, in_order: true)
  end

  def test_logs_without_timestamps_are_not_deduped
    logs_response_1_with_anomaly = logs_response_1 + "Line 3.5"
    logs_response_2_with_anomaly = "Line 3.5\n" + logs_response_2
    KubernetesDeploy::Kubectl.any_instance.stubs(:run)
      .returns([logs_response_1_with_anomaly, "", ""])
      .then.returns([logs_response_2_with_anomaly, "", ""])

    @logs.sync
    @logs.sync
    @logs.print_all
    assert_logs_match("Line 3.5", 2)
  end

  def test_deduplication_works_when_exact_same_batch_is_returned_more_than_once
    KubernetesDeploy::Kubectl.any_instance.stubs(:run)
      .returns([logs_response_1, "", ""])
      .then.returns([logs_response_1, "", ""])
      .then.returns([logs_response_2, "", ""])

    @logs.sync
    @logs.sync
    @logs.sync

    @logs.print_all
    assert_logs_match_all(generate_log_messages(1..10), in_order: true)
    assert_logs_match("Line 2", 1)
  end

  private

  def generate_log_messages(range)
    range.map { |i| "Line #{i}" }
  end

  def logs_response_1
    # beginning of logs from second 1
    <<~STRING
      2018-10-04T19:40:30.997382362Z Line 1
      2018-10-04T19:40:30.997941546Z Line 2
      2018-10-04T19:40:30.998388739Z Line 3
    STRING
  end

  def logs_response_2
    # all logs from second 1, beginning of logs from second 2
    <<~STRING
      2018-10-04T19:40:30.997382362Z Line 1
      2018-10-04T19:40:30.997941546Z Line 2
      2018-10-04T19:40:30.998388739Z Line 3
      2018-10-04T19:40:30.998903896Z Line 4
      2018-10-04T19:40:30.999372814Z Line 5
      2018-10-04T19:40:30.999913734Z Line 6
      2018-10-04T19:40:31.000440618Z Line 7
      2018-10-04T19:40:31.000831095Z Line 8
      2018-10-04T19:40:31.001315586Z Line 9
      2018-10-04T19:40:31.001828676Z Line 10
    STRING
  end

  def logs_response_3
    # all logs from second 2, beginning of logs from second 3
    <<~STRING
      2018-10-04T19:40:31.000440618Z Line 7
      2018-10-04T19:40:31.000831095Z Line 8
      2018-10-04T19:40:31.001315586Z Line 9
      2018-10-04T19:40:31.001828676Z Line 10
      2018-10-04T19:40:31.002302062Z Line 11
      2018-10-04T19:40:31.002838996Z Line 12
      2018-10-04T19:40:31.998063715Z Line 13
      2018-10-04T19:40:32.000261328Z Line 14
      2018-10-04T19:40:32.000569504Z Line 15
    STRING
  end
end
