# frozen_string_literal: true
require 'pry'

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

$LOAD_PATH.unshift(File.expand_path('../../lib', __FILE__))
require 'krane'
require 'kubernetes-deploy'
require 'kubeclient'
require 'timecop'
require 'minitest/autorun'
require 'minitest/stub/const'
require 'webmock/minitest'
require 'mocha/minitest'
require 'minitest/parallel'
require "minitest/reporters"
include(StatsD::Instrument::Assertions)

Dir.glob(File.expand_path("../helpers/*.rb", __FILE__)).each { |file| require file }

Mocha::Configuration.prevent(:stubbing_method_unnecessarily)
Mocha::Configuration.prevent(:stubbing_non_existent_method)
Mocha::Configuration.prevent(:stubbing_non_public_method)

if ENV["PARALLELIZE_ME"]
  Minitest::Reporters.use!([
    Minitest::Reporters::ParallelizableReporter.new(
      fast_fail: ENV['VERBOSE'] == '1',
      slow_count: 10,
      detailed_skip: false,
      verbose: ENV['VERBOSE'] == '1'
    ),
  ])
else
  Minitest::Reporters.use!([
    Minitest::Reporters::DefaultReporter.new(
      slow_count: 10,
      detailed_skip: false,
      verbose: ENV['VERBOSE'] == '1'
    ),
  ])
end

module KubernetesDeploy
  class TestCase < ::Minitest::Test
    attr_reader :logger

    def run
      ban_net_connect? ? WebMock.disable_net_connect! : WebMock.allow_net_connect!
      yield if block_given?
      super
    end

    def setup
      Kubectl.any_instance.expects(:run).never if ban_net_connect? # can't use mocha in Minitest::Test#run
      configure_logger
      @mock_output_stream = StringIO.new
    end

    def configure_logger
      @logger_stream = StringIO.new
      if log_to_real_fds?
        ColorizedString.disable_colorization = false

        # Allows you to view the integration test output as a series of tophat scenarios
        test_header = <<~MESSAGE

          \033[0;35m***************************************************************************
          Begin test: #{name}
          ***************************************************************************\033[0m

        MESSAGE
        test_header.each_line { |l| $stderr.puts l }
        device = $stderr
      else
        ColorizedString.disable_colorization = true
        device = @logger_stream
      end

      @logger = KubernetesDeploy::FormattedLogger.build(@namespace, KubeclientHelper::TEST_CONTEXT, device)
    end

    def ban_net_connect?
      true
    end

    def reset_logger
      return if log_to_real_fds?
      # Flush StringIO buffer if not closed
      unless @logger_stream.closed?
        @logger_stream.truncate(0)
        @logger_stream.rewind
      end
    end

    def assert_deploy_failure(result, cause = nil)
      assert_equal(false, result, "Deploy succeeded when it was expected to fail.#{logs_message_if_captured}")
      logging_assertion do |logs|
        cause_string = cause == :timed_out ? "TIMED OUT" : "FAILURE"
        assert_match Regexp.new("Result: #{cause_string}"), logs,
          "'Result: #{cause_string}' not found in the following logs:\n#{logs}"
      end
    end
    alias_method :assert_restart_failure, :assert_deploy_failure
    alias_method :assert_task_run_failure, :assert_deploy_failure

    def assert_deploy_success(result)
      assert_equal(true, result, "Deploy failed when it was expected to succeed.#{logs_message_if_captured}")
      logging_assertion do |logs|
        assert_match Regexp.new("Result: SUCCESS"), logs, "'Result: SUCCESS' not found in the following logs:\n#{logs}"
      end
    end
    alias_method :assert_restart_success, :assert_deploy_success
    alias_method :assert_task_run_success, :assert_deploy_success

    def assert_logs_match(regexp, times = nil)
      logging_assertion do |logs|
        unless times
          assert_match(regexp, logs, "'#{regexp}' not found in the following logs:\n#{logs}")
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
            assert(scanner.scan_until(regex), failure_msg)
          else
            assert(regex =~ logs, "'#{entry}' not found in the following logs:\n#{logs}")
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
      assert_match(exception_message, exception.message)
      exception
    end

    def fixture_path(set_name)
      source_dir = File.expand_path("../fixtures/#{set_name}", __FILE__)
      raise ArgumentError,
        "Fixture set #{set_name} does not exist as directory #{source_dir}" unless File.directory?(source_dir)
      source_dir
    end

    def stub_kubectl_response(*args, kwargs: {}, resp:, err: "", success: true, json: true, times: 1)
      if json
        kwargs[:output] = "json"
        resp = resp.to_json
      end
      response = [resp, err, stub(success?: success)]
      KubernetesDeploy::Kubectl.any_instance.expects(:run).with(*args, kwargs.presence).returns(response).times(times)
    end

    def build_runless_kubectl
      obj = KubernetesDeploy::Kubectl.new(namespace: 'test', context: KubeclientHelper::TEST_CONTEXT,
        logger: logger, log_failure_by_default: false)
      def obj.run(*)
        ["", "", SystemExit.new(0)]
      end
      obj
    end

    def logs_message_if_captured
      unless log_to_real_fds?
        " Logs:\n#{@logger_stream.string}"
      end
    end

    def mock_output_stream
      if log_to_real_fds?
        $stdout
      else
        @mock_output_stream
      end
    end

    def task_config(context: KubeclientHelper::TEST_CONTEXT, namespace: @namespace, logger: @logger)
      KubernetesDeploy::TaskConfig.new(context, namespace, logger)
    end

    def krane_black_box(command, args = "")
      path = File.expand_path("../../exe/krane", __FILE__)
      Open3.capture3("#{path} #{command} #{args}")
    end

    private

    def log_to_real_fds?
      ENV["PRINT_LOGS"] == "1"
    end

    def logging_assertion
      if log_to_real_fds?
        $stderr.puts("\033[0;33mWARNING: Skipping logging assertions while logs are redirected to stderr\033[0m")
      else
        yield @logger_stream.string
      end
    end

    def stdout_assertion
      if log_to_real_fds?
        $stderr.puts("\033[0;33mWARNING: Skipping stream assertions while logs are redirected to stderr\033[0m")
      else
        yield @mock_output_stream.string
      end
    end
  end
end
