# frozen_string_literal: true
require 'test_helper'

class PsychK8sPatchTest < Krane::TestCase

  INPUTS = [
      'a: "123e4"',
      'a: "123E4"',
      'a: "+123e4"',
      'a: "-123e4"',
      'a: "123e+4"',
      'a: "123e-4"',
      'a: "123.0e-4"'
  ]

  EXPECTED_DEACTIVATED = [
      %(---\n- a: 123e4\n), # Psych sees this as non-numeric; deviates from YAML 1.2 spec :(
      %(---\n- a: 123E4\n), # Psych sees this as non-numeric; deviates from YAML 1.2 spec :(
      %(---\n- a: "+123e4"\n), # Psych sees this as non-numeric; deviates from YAML 1.2 spec; quoted due to '+' :|
      %(---\n- a: "-123e4"\n), # Psych sees this as non-numeric; deviates from YAML 1.2 spec; quoted due to '-' :|
      %(---\n- a: 123e+4\n), # Psych sees this as non-numeric; deviates from YAML 1.2 spec :(
      %(---\n- a: 123e-4\n), # Psych sees this as non-numeric; deviates from YAML 1.2 spec :(
      %(---\n- a: '123.0e-4'\n), # Psych sees this as numeric; encapsulated with single quotes :)
  ]

  EXPECTED_ACTIVATED = [
      %(---\n- a: "123e4"\n),
      %(---\n- a: "123E4"\n),
      %(---\n- a: "+123e4"\n),
      %(---\n- a: "-123e4"\n),
      %(---\n- a: "123e+4"\n),
      %(---\n- a: "123e-4"\n),
      %(---\n- a: '123.0e-4'\n),
  ]

  def test_dump
    run_all_test_cases(->(n) { Psych.dump(n) })
  end

  def test_dump_stream
    run_all_test_cases(->(n) { Psych.dump_stream(n) })
  end

  def test_to_yaml
    run_all_test_cases(->(n) { n.to_yaml })
  end

  def run_all_test_cases(serializer)
    run_test_cases(INPUTS, EXPECTED_DEACTIVATED, serializer)
    run_test_cases_activated(INPUTS, EXPECTED_ACTIVATED, serializer)
  end

  def run_test_cases(inputs, expectations, serializer)
    (0..inputs.length - 1).each { |i|
      loaded = YAML.load_stream(inputs[i])
      assert_equal(expectations[i].strip, serializer.call(loaded).strip)
    }
  end

  def run_test_cases_activated(inputs, expectations, serializer)
    PsychK8sPatch.activate
    begin
      run_test_cases(inputs, expectations, serializer)
    ensure
      PsychK8sPatch.deactivate
    end
  end
end
