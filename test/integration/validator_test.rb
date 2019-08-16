# frozen_string_literal: true
require 'integration_test_helper'

class ValidatorTest < KubernetesDeploy::IntegrationTest
  def test_valid_configuration
    assert_predicate(validator(context: KubeclientHelper::TEST_CONTEXT, namespace: 'default'), :valid?)
  end

  def test_invalid_kubeconfig
    assert_match(/Context test-context missing from/, validator.errors.join("\n"))
  end

  def test_context_does_not_exists
    assert_match("Context test-context missing from your kubeconfig file(s)",
      validator.errors.join("\n"))
  end

  def test_namespace_does_not_exists
    assert_match(/Cloud not find Namespace: test-namespace in Context: #{KubeclientHelper::TEST_CONTEXT}/,
      validator(context: KubeclientHelper::TEST_CONTEXT).errors.join("\n"))
  end

  def test_invalid_server_version
    old_min_version = KubernetesDeploy::MIN_KUBE_VERSION
    new_min_version = "99999"
    KubernetesDeploy.const_set(:MIN_KUBE_VERSION, new_min_version)
    validator(context: KubeclientHelper::TEST_CONTEXT, namespace: 'default', logger: @logger).valid?
    assert_logs_match_all([
      "Minimum cluster version requirement of #{new_min_version} not met.",
    ])
  ensure
    KubernetesDeploy.const_set(:MIN_KUBE_VERSION, old_min_version)
  end

  private

  def validator(context: nil, namespace: nil, logger: nil)
    KubernetesDeploy::Validator.new(task_config(context: context, namespace: namespace, logger: logger))
  end

  def task_config(context: nil, namespace: nil, logger: nil)
    KubernetesDeploy::TaskConfig.new(context || "test-context", namespace || "test-namespace", logger)
  end
end
