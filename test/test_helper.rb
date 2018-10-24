# frozen_string_literal: true
if ENV["COVERAGE"]
  require 'simplecov'
  SimpleCov.start do
    add_filter 'test/'
  end

  if ENV["CODECOV_TOKEN"]
    require 'codecov'
    SimpleCov.formatter = SimpleCov::Formatter::Codecov
  end
end

if ENV["PROFILE"]
  require 'ruby-prof'
  require 'ruby-prof-flamegraph'
end

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'kubernetes-deploy'
require 'kubeclient'
require 'pry'
require 'timecop'
require 'minitest/autorun'
require 'minitest/stub/const'
require 'webmock/minitest'
require 'mocha/minitest'
require 'minitest/parallel'
require "minitest/reporters"
include StatsD::Instrument::Assertions

Dir.glob(File.expand_path("../helpers/*.rb", __FILE__)).each { |file| require file }
ENV["KUBECONFIG"] ||= "#{Dir.home}/.kube/config"

Mocha::Configuration.prevent(:stubbing_method_unnecessarily)
Mocha::Configuration.prevent(:stubbing_non_existent_method)
Mocha::Configuration.prevent(:stubbing_non_public_method)

if ENV["PARALLELIZE_ME"]
  Minitest::Reporters.use! [
    Minitest::Reporters::ParallelizableReporter.new(
      fast_fail: ENV['VERBOSE'] == '1',
      slow_count: 10,
      detailed_skip: false,
      verbose: ENV['VERBOSE'] == '1'
    )
  ]
else
  Minitest::Reporters.use! [
    Minitest::Reporters::DefaultReporter.new(
      slow_count: 10,
      detailed_skip: false,
      verbose: ENV['VERBOSE'] == '1'
    )
  ]
end

module KubernetesDeploy
  class TestCase < ::Minitest::Test
    def setup
      if ban_net_connect?
        Kubectl.any_instance.expects(:run).never
        WebMock.disable_net_connect!
      end
      @logger_stream = StringIO.new

      if log_to_stderr?
        ColorizedString.disable_colorization = false
        # Allows you to view the integration test output as a series of tophat scenarios
        <<~MESSAGE.each_line { |l| $stderr.puts l }

          \033[0;35m***************************************************************************
           Begin test: #{name}
          ***************************************************************************\033[0m

        MESSAGE
      else
        ColorizedString.disable_colorization = true
      end
    end

    def ban_net_connect?
      true
    end

    def logger
      @logger ||= begin
        device = log_to_stderr? ? $stderr : @logger_stream
        KubernetesDeploy::FormattedLogger.build(@namespace, KubeclientHelper::TEST_CONTEXT, device)
      end
    end

    def teardown
      @logger_stream.close
    end

    def reset_logger
      @logger = nil
      # Flush StringIO buffer if not closed
      unless @logger_stream.closed?
        @logger_stream.truncate(0)
        @logger_stream.rewind
      end
    end

    def assert_deploy_failure(result, cause = nil)
      if log_to_stderr?
        assert_equal false, result, "Deploy succeeded when it was expected to fail"
        return
      end

      logging_assertion do |logs|
        cause_string = cause == :timed_out ? "TIMED OUT" : "FAILURE"
        assert_match Regexp.new("Result: #{cause_string}"), logs,
          "'Result: #{cause_string}' not found in the following logs:\n#{logs}"
        assert_equal false, result, "Deploy succeeded when it was expected to fail. Logs:\n#{logs}"
      end
    end
    alias_method :assert_restart_failure, :assert_deploy_failure
    alias_method :assert_task_run_failure, :assert_deploy_failure

    def assert_deploy_success(result)
      if log_to_stderr?
        assert_equal true, result, "Deploy failed when it was expected to succeed"
        return
      end

      logging_assertion do |logs|
        assert_equal true, result, "Deploy failed when it was expected to succeed. Logs:\n#{logs}"
        assert_match Regexp.new("Result: SUCCESS"), logs, "'Result: SUCCESS' not found in the following logs:\n#{logs}"
      end
    end
    alias_method :assert_restart_success, :assert_deploy_success
    alias_method :assert_task_run_success, :assert_deploy_success

    def assert_logs_match(regexp, times = nil)
      logging_assertion do |logs|
        unless times
          assert_match regexp, logs, "'#{regexp}' not found in the following logs:\n#{logs}"
          return
        end

        count = logs.scan(regexp).count
        fail_msg = "Expected #{regexp} to appear #{times} time(s) in the log, but it appeared #{count} times"
        assert_equal times, count, fail_msg
      end
    end

    def assert_logs_match_all(entry_list, in_order: false)
      logging_assertion do |logs|
        scanner = StringScanner.new(logs)
        entry_list.each do |entry|
          regex = entry.is_a?(Regexp) ? entry : Regexp.new(Regexp.escape(entry))
          if in_order
            failure_msg = "'#{entry}' not found in the expected sequence in the following logs:\n#{logs}"
            assert scanner.scan_until(regex), failure_msg
          else
            assert regex =~ logs, "'#{entry}' not found in the following logs:\n#{logs}"
          end
        end
      end
    end

    def refute_logs_match(regexp)
      logging_assertion do |logs|
        regexp = regexp.is_a?(Regexp) ? regexp : Regexp.new(Regexp.escape(regexp))
        refute regexp =~ logs, "Expected '#{regexp}' not to appear in the following logs:\n#{logs}"
      end
    end

    def assert_raises(*exp, message: nil)
      case exp.last
      when String, Regexp
        raise ArgumentError, "Please use the kwarg message instead of the positional one.\n"\
          "To assert the message exception, use `assert_raises_message` or the return value of `assert_raises`"
      else
        exp += Array(message)
        super(*exp) { yield }
      end
    end

    def assert_raises_message(exception_class, exception_message)
      exception = assert_raises(exception_class) { yield }
      assert_match exception_message, exception.message
      exception
    end

    def fixture_path(set_name)
      source_dir = File.expand_path("../fixtures/#{set_name}", __FILE__)
      raise ArgumentError,
        "Fixture set #{set_name} does not exist as directory #{source_dir}" unless File.directory?(source_dir)
      source_dir
    end

    def stub_kubectl_response(*args, resp:, err: "", raise_if_not_found: nil, success: true, json: true, times: 1)
      resp = resp.to_json if json
      response = [resp, err, stub(success?: success)]

      expectation = if raise_if_not_found.nil?
        KubernetesDeploy::Kubectl.any_instance.expects(:run).with(*args)
      else
        KubernetesDeploy::Kubectl.any_instance.expects(:run).with(*args, raise_if_not_found: raise_if_not_found)
      end

      expectation.returns(response).times(times)
    end

    def build_runless_kubectl
      obj = KubernetesDeploy::Kubectl.new(namespace: 'test', context: KubeclientHelper::TEST_CONTEXT,
        logger: logger, log_failure_by_default: false)
      def obj.run(*)
        ["", "", SystemExit.new(0)]
      end
      obj
    end

    private

    def log_to_stderr?
      ENV["PRINT_LOGS"] == "1"
    end

    def logging_assertion
      if log_to_stderr?
        $stderr.puts("\033[0;33mWARNING: Skipping logging assertions while logs are redirected to stderr\033[0m")
      else
        @logger_stream.rewind
        yield @logger_stream.read
      end
    end
  end
end
