# frozen_string_literal: true
require 'test_helper'

class FormattedLoggerTest < KubernetesDeploy::TestCase
  def test_build
    new_logger = KubernetesDeploy::FormattedLogger.build('test-ns', 'minikube', @logger_stream)
    assert(new_logger.is_a?(::Logger))
    assert_equal(::Logger::INFO, new_logger.level)
    refute_nil(new_logger.formatter)
  end

  def test_debug_log_level_from_env
    original_env = ENV["DEBUG"]
    ENV["DEBUG"] = "lol"
    new_logger = KubernetesDeploy::FormattedLogger.build('test-ns', 'minikube', @logger_stream)
    assert_equal(::Logger::DEBUG, new_logger.level)
  ensure
    ENV["DEBUG"] = original_env
  end

  def test_warn_log_level_from_env
    original_env = ENV["LEVEL"]
    ENV["LEVEL"] = "warn"
    new_logger = KubernetesDeploy::FormattedLogger.build('test-ns', 'minikube', @logger_stream)
    assert_equal(::Logger::WARN, new_logger.level)
  ensure
    ENV["LEVEL"] = original_env
  end

  def test_verbose_tag_mode
    new_logger = KubernetesDeploy::FormattedLogger.build('test-ns', 'minikube', @logger_stream, verbose_prefix: true)
    new_logger.info("This should have namespace and context information")
    assert_logs_match(/^\[INFO\].*\[minikube\]\[test-ns\]\tThis should have namespace and context information$/)
  end

  def test_blank_line
    new_logger = KubernetesDeploy::FormattedLogger.build('test-ns', 'minikube', @logger_stream)
    new_logger.info("FYI")
    new_logger.blank_line
    new_logger.warn("Warning")
    new_logger.blank_line(:warn)
    new_logger.error("Error")
    new_logger.blank_line(:fatal)
    new_logger.fatal("Fatal")

    # example output
    # [INFO][2017-05-19 20:07:31 -0400]\tFYI
    # [INFO][2017-05-19 20:07:31 -0400]\t
    # [WARN][2017-05-19 20:07:31 -0400]\tWarning
    # [WARN][2017-05-19 20:07:31 -0400]\t
    # [ERROR][2017-05-19 20:07:31 -0400]\tError
    # [FATAL][2017-05-19 20:07:31 -0400]\t
    # [FATAL][2017-05-19 20:07:31 -0400]\tFatal

    entries = [
      /^\[INFO\].*\]\tFYI$/,
      /^\[INFO\].*\]\t$/,
      /^\[WARN\].*\]\tWarning$/,
      /^\[WARN\].*\]\t$/,
      /^\[ERROR\].*\]\tError$/,
      /^\[FATAL\].*\]\t$/,
      /^\[FATAL\].*\]\tFatal$/,
    ]
    assert_logs_match_all(entries, in_order: true)
  end
end
