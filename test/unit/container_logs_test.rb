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

    assert_equal(generate_log_messages(1..15), @logs.lines)
  end

  def test_sync_handles_cycles_where_no_new_logs_available
    KubernetesDeploy::Kubectl.any_instance.stubs(:run)
      .returns([logs_response_1, "", ""])
      .then.returns(["", "", ""])
      .then.returns([logs_response_2, "", ""])
    @logs.sync
    @logs.sync
    @logs.sync

    assert_equal(generate_log_messages(1..10), @logs.lines)
  end

  def test_empty_delegated_to_lines
    KubernetesDeploy::Kubectl.any_instance.stubs(:run).returns([logs_response_1, "", ""])
    assert_predicate(@logs, :empty?)
    @logs.sync
    refute_predicate(@logs, :empty?)
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
      "[A]  Line 3",
    ]
    @logs.print_latest(prefix: true)
    assert_logs_match_all(expected, in_order: true)
  end

  def test_logs_without_timestamps_are_not_deduped
    logs_response_1_with_anomaly = logs_response_1 + "No timestamp"
    logs_response_2_with_anomaly = "No timestamp 2\n" + logs_response_2
    KubernetesDeploy::Kubectl.any_instance.stubs(:run)
      .returns([logs_response_1_with_anomaly, "", ""])
      .then.returns([logs_response_2_with_anomaly, "", ""])

    @logs.sync
    @logs.sync
    @logs.print_all
    assert_logs_match_all([
      "No timestamp", # moved to start of batch 1
      "Line 1",
      "Line 2",
      "Line 3",
      "No timestamp 2", # moved to start of batch 2
      "Line 4",
    ], in_order: true)
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

  def test_deduplication_works_when_last_line_is_out_of_order
    regression_data = <<~STRING
      2018-12-13T12:17:23.727605598Z Line 1
      2018-12-13T12:17:23.727696012Z Line 2
      2018-12-13T12:17:23.728538913Z Line 3
      2018-12-13T12:17:23.7287293Z Line 4
      2018-12-13T12:17:23.729694842Z Line 5
      2018-12-13T12:17:23.731259592Z Line 7
      2018-12-13T12:17:23.73127007Z Line 8
      2018-12-13T12:17:23.731273672Z Line 9
      2018-12-13T12:17:23.731276862Z Line 10
      2018-12-13T12:17:23.731284069Z Line 11
      2018-12-13T12:17:23.731287054Z Line 12
      2018-12-13T12:17:23.731289959Z Line 13
      2018-12-13T12:17:23.731292814Z Line 14
      2018-12-13T12:17:23.731295298Z Line 15
      2018-12-13T12:17:23.731297747Z Line 16
      2018-12-13T12:17:23.731297748Z Line 17
      2018-12-13T12:17:23.729851532Z Line 6
    STRING

    KubernetesDeploy::Kubectl.any_instance.stubs(:run)
      .returns([regression_data, "", ""]).times(12)

    12.times do
      @logs.sync
      @logs.print_latest
    end

    expected_lines = generate_log_messages(1..17)

    expected_lines.each do |line|
      assert_logs_match(/#{line}$/, 1) # no duplicates
    end
    assert_logs_match_all(expected_lines, in_order: true) # sorted correctly
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
