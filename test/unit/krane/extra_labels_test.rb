# frozen_string_literal: true
require 'test_helper'
require 'krane/extra_labels'

class ExtraLabelsTest < ::Minitest::Test
  def test_parse_extra_labels
    expected = { "foo" => "42", "bar" => "17" }
    assert_equal(expected, parse("foo=42,bar=17"))
  end

  def test_parse_extra_labels_with_equality_sign
    expected = { "foo" => "1=2=3", "bar" => "3", "bla" => "4=7" }
    assert_equal(expected, parse("foo=1=2=3,bar=3,bla=4=7"))
  end

  def test_parse_extra_labels_with_no_value
    expected = { "bla" => nil, "foo" => "" }
    assert_equal(expected, parse("bla,foo="))
  end

  def test_parse_extra_labels_with_no_key
    assert_raises(ArgumentError, "key is blank") do
      parse("=17,foo=42")
    end
  end

  private

  def parse(string)
    Krane::ExtraLabels.parse(string).to_h
  end
end
