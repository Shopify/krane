# frozen_string_literal: true
require 'test_helper'

class TaskConfigTest < KubernetesDeploy::TestCase
  def test_responds_to_namespace
    assert_equal(task_config.namespace, "test-namespace")
  end

  def test_responds_to_context
    assert_equal(task_config.context, "test-context")
  end

  def test_builds_a_logger_if_none_provided
    assert_equal(task_config.logger.class, KubernetesDeploy::FormattedLogger)
  end

  def test_uses_provided_logger
    logger = KubernetesDeploy::FormattedLogger.build(nil, nil)
    assert_equal(task_config(logger: logger).logger, logger)
  end

  private

  def task_config(context: nil, namespace: nil, logger: nil)
    KubernetesDeploy::TaskConfig.new(context || "test-context", namespace || "test-namespace", logger)
  end
end
