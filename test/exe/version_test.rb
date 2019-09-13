# frozen_string_literal: true
require 'test_helper'
require 'krane/cli/krane'

class VersionTest < KubernetesDeploy::TestCase
  def test_version_prints_current_version
    assert_output(/krane #{KubernetesDeploy::VERSION}/) { krane.version }
  end

  def test_version_success_as_black_box
    out, err, status = krane_black_box("version")
    assert_predicate(status, :success?)
    assert_empty(err)
    assert_match(KubernetesDeploy::VERSION, out)
  end

  def test_version_failure_as_black_box
    out, err, status = krane_black_box("version", "-q")
    assert_equal(status.exitstatus, 1)
    assert_empty(out)
    assert_match("ERROR", err)
  end

  private

  def krane
    Krane::CLI::Krane.new
  end
end
