# frozen_string_literal: true
require 'test_helper'
require 'json'

class BindingsParserTest < ::Minitest::Test
  def test_parse_json
    expected = { "foo" => 42, "bar" => "hello" }
    assert_equal expected, parse(expected.to_json)
  end

  def test_parse_complex_json
    expected = { "foo" => 42, "bar" => [1, 2, 3], "bla" => { "hello" => 17 } }
    assert_equal expected, parse(expected.to_json)
  end

  def test_parse_json_not_hash
    assert_raises(ArgumentError) do
      parse([1, 2, 3].to_json)
    end
  end

  def test_parse_csv
    expected = { "foo" => "42", "bar" => "17" }
    assert_equal expected, parse("foo=42,bar=17")
  end

  def test_parse_csv_with_comma_in_values
    expected = { "foo" => "a,b,c", "bar" => "d", "bla" => "e,f" }
    assert_equal expected, parse('"foo=a,b,c",bar=d,"bla=e,f"')
  end

  def test_parse_csv_with_equality_sign
    expected = { "foo" => "1=2=3", "bar" => "3", "bla" => "4=7" }
    assert_equal expected, parse("foo=1=2=3,bar=3,bla=4=7")
  end

  def test_parse_csv_with_no_value
    expected = { "bla" => nil, "foo" => "" }
    assert_equal expected, parse("bla,foo=")
  end

  def test_parse_csv_with_no_key
    assert_raises(ArgumentError) do
      parse("=17,foo=42")
    end
  end

  private

  def parse(string)
    KubernetesDeploy::BindingsParser.parse(string)
  end
end
