# frozen_string_literal: true
require 'test_helper'

class PsychK8sCompatibilityTest < Krane::TestCase
  TEST_CASES = {
    'a: "123e4"' => %(---\n- a: "123e4"\n),
    'a: "123E4"' => %(---\n- a: "123E4"\n),
    'a: "+123e4"' => %(---\n- a: "+123e4"\n),
    'a: "-123e4"' => %(---\n- a: "-123e4"\n),
    'a: "123e+4"' => %(---\n- a: "123e+4"\n),
    'a: "123e-4"' => %(---\n- a: "123e-4"\n),
    'a: "123.0e-4"' => %(---\n- a: "123.0e-4"\n),
  }

  def test_dump_k8s_compatible
    TEST_CASES.each do |input, expected|
      loaded = YAML.load_stream(input)
      output = YAML.dump_k8s_compatible(loaded)
      assert_equal(expected.strip, output.strip)
    end
  end

  def test_dump_stream_k8s_compatible
    TEST_CASES.each do |input, expected|
      loaded = YAML.load_stream(input)
      output = YAML.dump_stream_k8s_compatible(loaded)
      assert_equal(expected.strip, output.strip)
    end
  end
end
