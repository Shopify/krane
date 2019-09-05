# frozen_string_literal: true
require 'test_helper'
require 'krane/cli/krane'

class RestartTest < KubernetesDeploy::TestCase
  def test_restart_prints_current_version
    assert_output(/krane #{KubernetesDeploy::VERSION}/) { krane.restart }
  end

  def test_restart_success_as_black_box
    out, err, status = krane_black_box("restart")
    assert_predicate(status, :success?)
    assert_empty(err)
    assert_match(KubernetesDeploy::VERSION, out)
  end

  def test_restart_failure_as_black_box
    out, err, status = krane_black_box("restart", "-q")
    assert_equal(status.exitstatus, 1)
    assert_empty(out)
    assert_match("ERROR", err)
  end

  private

  def krane
    Krane::CLI::Krane.new
  end

  def krane_black_box(command, args = "")
    path = File.expand_path("../../../exe/krane", __FILE__)
    Open3.capture3("#{path} #{command} #{args}")
  end
end
