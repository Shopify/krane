# frozen_string_literal: true

# Usage: Extend a descendant of Minitest::Test with this module
# and then add "__Nretries" to the end of the names of the tests you want to retry up to N times if they fail
module AddRetriesTestHelper
  # ENV["VERBOSE"] example:
  #  KubernetesDeployTest#test_hpa_can_be_successful_and_gets_pruned__2retries 0.58 = F
  #  KubernetesDeployTest#test_hpa_can_be_successful_and_gets_pruned__2retries (Retry 1/2) 0.53 = F
  #  KubernetesDeployTest#test_hpa_can_be_successful_and_gets_pruned__2retries (Retry 2/2) 0.52 = F

  # !ENV["VERBOSE"] example:
  #   F Retry1/2:F Retry2/2:F
  def run_one_method(klass, method_name, reporter)
    match_data = method_name.match(/__(?<retries>\d+)retries$/)
    return super unless match_data && match_data[:retries]
    retries = match_data[:retries].to_i
    result = nil

    (retries + 1).times do |retry_num|
      result = Minitest.run_one_method(self, method_name) # The verbose reporter prints the test name here

      if retry_num > 0
        ENV["VERBOSE"] ? print("(Retry #{retry_num}/#{retries}) ") : print(" Retry#{retry_num}/#{retries}:")
      end

      break if result.passed? || retry_num == retries # the reporter will record the stuff below

      ENV["VERBOSE"] ? print("#{result.time.round(2)} = \033[0;31mF\033[0m") : print("\033[0;31mF\033[0m")
    end

    reporter.record(result)
  end
end
