# frozen_string_literal: true
require 'test_helper'

class DurationParserTest < KubernetesDeploy::TestCase
  def test_parses_correct_iso_durations_with_prefixes
    assert_equal 300, new_parser("PT300S").parse!
    assert_equal 300, new_parser("PT5M").parse!
    assert_equal 900, new_parser("PT0.25H").parse!
    assert_equal 110839937, new_parser("P3Y6M4DT12H30M5S").parse!
  end

  def test_parses_correct_iso_durations_without_prefixes
    assert_equal 300, new_parser("300S").parse!
    assert_equal 300, new_parser("5M").parse!
    assert_equal 900, new_parser("0.25H").parse!
    assert_equal(-60, new_parser("-1M").parse!)
  end

  def test_parse_is_case_insensitive
    assert_equal 30, new_parser("30S").parse!
    assert_equal 30, new_parser("30s").parse!
    assert_equal 30, new_parser("pt30s").parse!
    assert_equal 110839937, new_parser("p3y6M4dT12H30M5s").parse!
  end

  def test_parse_raises_expected_error_for_blank_values
    ["", "   ", nil].each do |blank_value|
      expected_msg = 'Invalid ISO 8601 duration: "" is empty duration'
      assert_raises_message(KubernetesDeploy::DurationParser::ParsingError, expected_msg) do
        new_parser(blank_value).parse!
      end
    end
  end

  def test_extra_whitespace_is_stripped_from_values
    assert_equal 30, new_parser("  30S    ").parse!
  end

  def test_parse_raises_expected_error_when_value_is_invalid
    assert_raises_message(KubernetesDeploy::DurationParser::ParsingError, 'Invalid ISO 8601 duration: "FOO"') do
      new_parser("foo").parse!
    end
  end

  private

  def new_parser(value)
    KubernetesDeploy::DurationParser.new(value)
  end
end
