# frozen_string_literal: true
require 'test_helper'
require 'json'
require 'kubernetes-deploy/bindings_parser'

class BindingsParserTest < ::Minitest::Test
  def test_parse_json
    expected = { "foo" => 42, "bar" => "hello" }
    assert_equal(expected, parse(expected.to_json))
  end

  def test_parse_json_file
    expected = { "foo" => "a,b,c", "bar" => "d", "bla" => "e,f" }
    assert_equal(expected, parse("@test/fixtures/for_unit_tests/bindings.json"))
  end

  def test_parse_yaml_file_with_yml_ext
    expected = { "foo" => "a,b,c", "bar" => "d", "bla" => "e,f", "nes" => { "ted" => "bar" } }
    assert_equal(expected, parse("@test/fixtures/for_unit_tests/bindings.yml"))
  end

  def test_parse_yaml_file_with_yaml_ext
    expected = { "foo" => "a,b,c", "bar" => "d", "bla" => "e,f", "nes" => { "cats" => "awesome", "ted" => "foo" } }
    assert_equal(expected, parse("@test/fixtures/for_unit_tests/bindings.yaml"))
  end

  def test_parse_nonexistent_file
    assert_raises(ArgumentError) do
      parse("@fake/file.json")
    end
  end

  def test_parse_invalid_file_type
    assert_raises(ArgumentError) do
      parse("@fake/file.ini")
    end
  end

  def test_parse_complex_json
    expected = { "foo" => 42, "bar" => [1, 2, 3], "bla" => { "hello" => 17 } }
    assert_equal(expected, parse(expected.to_json))
  end

  def test_parse_json_not_hash
    assert_raises(ArgumentError) do
      parse([1, 2, 3].to_json)
    end
  end

  def test_parse_csv
    expected = { "foo" => "42", "bar" => "17" }
    assert_equal(expected, parse("foo=42,bar=17"))
  end

  def test_parse_csv_with_comma_in_values
    expected = { "foo" => "a,b,c", "bar" => "d", "bla" => "e,f" }
    assert_equal(expected, parse('"foo=a,b,c",bar=d,"bla=e,f"'))
  end

  def test_parse_csv_with_equality_sign
    expected = { "foo" => "1=2=3", "bar" => "3", "bla" => "4=7" }
    assert_equal(expected, parse("foo=1=2=3,bar=3,bla=4=7"))
  end

  def test_parse_csv_with_no_value
    expected = { "bla" => nil, "foo" => "" }
    assert_equal(expected, parse("bla,foo="))
  end

  def test_parse_csv_with_no_key
    assert_raises(ArgumentError) do
      parse("=17,foo=42")
    end
  end

  def test_parse_nested_values
    expected = { "foo" => "a,b,c", "bar" => "d", "bla" => "e,f", "nes" => { "cats" => "awesome", "ted" => "bar" } }
    bindings = KubernetesDeploy::BindingsParser.new
    ["@test/fixtures/for_unit_tests/bindings.yaml", "@test/fixtures/for_unit_tests/bindings.yml"].each do |b|
      bindings.add(b)
    end
    assert_equal(expected, bindings.parse)
  end

  def test_parses_yaml_file_with_aliases
    expected = { "foo" => "a,b,c", "bar" => { "baz" => "bang" }, "alias" => { "baz" => "bang" } }
    bindings = KubernetesDeploy::BindingsParser.new
    bindings.add('@test/fixtures/for_unit_tests/bindings-with-aliases.yaml')
    assert_equal(expected, bindings.parse)
  end

  private

  def parse(string)
    KubernetesDeploy::BindingsParser.parse(string)
  end
end
