# frozen_string_literal: true
require 'test_helper'

class TaskConfigTest < KubernetesDeploy::TestCase
  def test_responds_to_namespace
    namespace = "test-namespace"
    assert_equal(task_config(namespace: namespace).namespace, namespace)
  end

  def test_responds_to_context
    context = "test-context"
    assert_equal(task_config(context: "test-context").context, context)
  end

  def test_builds_a_logger_if_none_provided
    assert_equal(task_config(logger: nil).logger.class, KubernetesDeploy::FormattedLogger)
  end

  def test_uses_provided_logger
    logger = KubernetesDeploy::FormattedLogger.build(nil, nil)
    assert_equal(task_config(logger: logger).logger, logger)
  end
end
