# frozen_string_literal: true
require 'test_helper'

class RemoteLogsTest < KubernetesDeploy::TestCase
  def test_print_latest_uses_prefix_if_multiple_containers
    logs = build_remote_logs(container_names: %w(Container1 ContainerA))
    logs.container_logs.first.expects(:lines).returns(mock_lines(1..4)).at_least_once
    logs.container_logs.last.expects(:lines).returns(mock_lines('A'..'D')).at_least_once

    logs.print_latest
    assert_logs_match_all([
      "[Container1]  Line 1",
      "[Container1]  Line 2",
      "[Container1]  Line 3",
      "[Container1]  Line 4",
      "[ContainerA]  Line A",
      "[ContainerA]  Line B",
      "[ContainerA]  Line C",
      "[ContainerA]  Line D",
    ], in_order: true)
  end

  def test_print_latest_does_not_use_prefix_if_one_container
    logs = build_remote_logs(container_names: %w(A))
    logs.container_logs.first.expects(:lines).returns(mock_lines(1..4)).at_least_once

    logs.print_latest
    assert_logs_match_all(mock_lines(1..4), in_order: true)
    refute_logs_match("[Container1]")
  end

  def test_print_all_prints_custom_message_if_no_logs_at_all
    logs = build_remote_logs(container_names: %w(A))
    logs.print_all
    assert_logs_match(%r{No logs found for pod/pod-123-456})
  end

  def test_print_all_prints_custom_message_if_one_container_has_no_logs
    logs = build_remote_logs(container_names: %w(Container1 ContainerA))
    logs.container_logs.first.expects(:lines).returns([]).at_least_once
    logs.container_logs.last.expects(:lines).returns(mock_lines('A'..'D')).at_least_once

    logs.print_all
    assert_logs_match_all([
      "No logs found for pod/pod-123-456 container 'Container1'",
      "Logs from pod/pod-123-456 container 'ContainerA'",
      "Line A",
      "Line B",
      "Line C",
      "Line D",
    ], in_order: true)
  end

  def test_print_all_identifies_logs_from_all_containers
    logs = build_remote_logs(container_names: %w(Container1 ContainerA))
    logs.container_logs.first.expects(:lines).returns(mock_lines(1..4)).at_least_once
    logs.container_logs.last.expects(:lines).returns(mock_lines('A'..'D')).at_least_once

    logs.print_all
    assert_logs_match_all([
      "Logs from pod/pod-123-456 container 'Container1'",
      "Line 1",
      "Line 2",
      "Line 3",
      "Line 4",
      "Logs from pod/pod-123-456 container 'ContainerA'",
      "Line A",
      "Line B",
      "Line C",
      "Line D",
    ], in_order: true)
  end

  def test_print_all_suppresses_duplicate_output_by_default
    logs = build_remote_logs(container_names: %w(Container1))
    logs.container_logs.first.expects(:lines).returns(mock_lines(1..4)).at_least_once

    logs.print_all
    logs.print_all
    assert_logs_match("Line 1", 1)

    logs.print_all(prevent_duplicate: false)
    assert_logs_match("Line 1", 2)
  end

  private

  def build_remote_logs(container_names:)
    KubernetesDeploy::RemoteLogs.new(parent_id: 'pod/pod-123-456', logger: logger,
      container_names: container_names, namespace: 'test', context: KubeclientHelper::TEST_CONTEXT)
  end

  def mock_lines(range)
    range.map { |i| "Line #{i}" }
  end
end
