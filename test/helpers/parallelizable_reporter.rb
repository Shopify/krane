# frozen_string_literal: true
module Minitest
  module Reporters
    class ParallelizableReporter < DefaultReporter
      def on_record(test)
        # do not print the marks if test names are also printed
        # paralellism causes the names and results to be mismatched
        unless options[:verbose]
          # Print the pass/skip/fail mark
          result = if test.passed?
            record_pass(test)
          elsif test.skipped?
            record_skip(test)
          elsif test.failure
            record_failure(test)
          end
          print(result)
        end

        # Print fast_fail information
        return unless @fast_fail && test.failure # test.failure includes skips
        return if test.skipped? && !@detailed_skip
        puts "\n"
        print_failure(test)
      end
    end
  end
end
