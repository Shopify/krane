# frozen_string_literal: true
require 'integration_test_helper'

class TaskConfigValidatorTest < KubernetesDeploy::IntegrationTest
  def test_valid_configuration
    assert_predicate(validator(context: KubeclientHelper::TEST_CONTEXT, namespace: 'default'), :valid?)
  end

  def test_only_is_respected
    assert_predicate(validator(only: []), :valid?)
  end

  def test_invalid_kubeconfig
    bad_file = "/IM_NOT_A_REAL_FILE.yml"
    builder = KubernetesDeploy::KubeclientBuilder.new(kubeconfig: bad_file)
    assert_match("Kubeconfig not found at #{bad_file}",
      validator(kubeclient_builder: builder, only: [:validate_kubeconfig]).errors.join("\n"))
  end

  def test_context_does_not_exists_in_kubeconfig
    fake_context = "fake-context"
    assert_match(/Context #{fake_context} missing from your kubeconfig file/,
      validator(context: fake_context).errors.join("\n"))
  end

  def test_context_not_reachable
    fake_context = "fake-context"
    assert_match(/Something went wrong connecting to #{fake_context}/,
      validator(context: fake_context, only: [:validate_context_reachable]).errors.join("\n"))
  end

  def test_namespace_does_not_exists
    assert_match(/Could not find Namespace: test-namespace in Context: #{KubeclientHelper::TEST_CONTEXT}/,
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

  def validator(context: nil, namespace: nil, logger: nil, kubeclient_builder: nil, only: nil)
    context ||= "test-context"
    namespace ||= "test-namespace"
    config = task_config(context: context, namespace: namespace, logger: logger)
    kubectl = KubernetesDeploy::Kubectl.new(namespace: config.namespace,
      context: config.context, logger: config.logger, log_failure_by_default: true)
    kubeclient_builder ||= KubernetesDeploy::KubeclientBuilder.new
    KubernetesDeploy::TaskConfigValidator.new(config, kubectl, kubeclient_builder, only: only)
  end
end
