# frozen_string_literal: true
require 'test_helper'

class LabelSelectorTest < ::Minitest::Test
  def test_parse_selector
    expected = { "foo" => "42", "bar" => "17" }
    assert_equal(expected, parse("foo=42,bar=17"))
  end

  def test_parse_selector_with_equality_sign
    expected = { "foo" => "1=2=3", "bar" => "3", "bla" => "4=7" }
    assert_equal(expected, parse("foo=1=2=3,bar=3,bla=4=7"))
  end

  def test_parse_selector_with_no_value
    expected = { "bla" => nil, "foo" => "" }
    assert_equal(expected, parse("bla,foo="))
  end

  def test_parse_selector_doubleeq
    expected = { "foo" => "=42" }
    assert_equal(expected, parse("foo==42"))
  end

  def test_parse_selector_noteq
    expected = { "foo!" => "42" }
    assert_equal(expected, parse("foo!=42"))
  end

  def test_parse_selector_with_no_key
    assert_raises(ArgumentError) do
      parse("=17,foo=42")
    end
  end

  private

  def parse(string)
    KubernetesDeploy::LabelSelector.parse(string).to_h
  end
end
