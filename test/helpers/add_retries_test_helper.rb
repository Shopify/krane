# frozen_string_literal: true

# Usage: Extend a descendant of Minitest::Test with this module
# and then add "__Nretries" to the end of the names of the tests you want to retry up to N times if they fail
module AddRetriesTestHelper
  def run_one_method(klass, method_name, reporter)
    match_data = method_name.match(/__(?<retries>\d+)retries$/)
    return super unless match_data && match_data[:retries]
    retries = match_data[:retries].to_i

    (retries + 1).times do |i|
      print(" Retry#{i}/#{retries}:") if i > 0 && !ENV["VERBOSE"]
      result = Minitest.run_one_method(self, method_name)
      reporter.record(result)
      print(" (Retry #{i}/#{retries})") if i > 0 && ENV["VERBOSE"]
      break if result.passed?
    end
  end
end
