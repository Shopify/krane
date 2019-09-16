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
end
