# frozen_string_literal: true
require 'test_helper'
require 'krane/cli/krane'

class KraneTest < KubernetesDeploy::TestCase
  def test_help_success_as_black_box
    _, err, status = krane_black_box("help")
    assert_predicate(status, :success?)
    assert_empty(err)
  end

  def test_krane_success_as_black_box
    _, err, status = krane_black_box("")
    assert_predicate(status, :success?)
    assert_empty(err)
  end

  private

  def krane_black_box(command, args = "")
    path = File.expand_path("../../../exe/krane", __FILE__)
    Open3.capture3("#{path} #{command} #{args}")
  end
end
