# frozen_string_literal: true
require 'test_helper'

class LoggerTest < KubernetesDeploy::TestCase
  def setup
    # don't use the test logger
    KubernetesDeploy.logger = nil
  end

  def teardown
    # reset to the test logger
    KubernetesDeploy.logger = @logger
  end

  def test_real_logger
    prod_logger = KubernetesDeploy.logger
    assert prod_logger.is_a?(::Logger)
    assert prod_logger.instance_variable_get(:@logdev).dev == ::STDERR, "This was not the actual production logger"
    assert_equal ::Logger::INFO, prod_logger.level
    refute_nil prod_logger.formatter
  end

  def test_debug_log_level_from_env
    original_env = ENV["DEBUG"]
    ENV["DEBUG"] = "lol"
    prod_logger = KubernetesDeploy.logger
    assert_equal ::Logger::DEBUG, prod_logger.level
  ensure
    ENV["DEBUG"] = original_env
  end

  def test_warn_log_level_from_env
    original_env = ENV["LEVEL"]
    ENV["LEVEL"] = "warn"
    prod_logger = KubernetesDeploy.logger
    assert_equal ::Logger::WARN, prod_logger.level
  ensure
    ENV["LEVEL"] = original_env
  end
end
