# frozen_string_literal: true
require 'test_helper'

class TaskConfigValidatorUnitTest < Krane::TestCase
  def test_namespace_that_would_be_parsed_as_a_kubectl_flag_is_rejected
    kubectl = mock('kubectl')
    kubectl.expects(:run).never

    validator = build_validator(namespace: "--server=http://127.0.0.1:8080", kubectl: kubectl,
      only: [:validate_namespace_exists])

    assert_equal(["Namespace is not a valid Kubernetes namespace name"], validator.errors)
  end

  def test_namespace_that_is_not_a_dns_label_is_rejected
    kubectl = mock('kubectl')
    kubectl.expects(:run).never

    ["UPPERCASE", "has spaces", "trailing-", "a" * 64].each do |namespace|
      validator = build_validator(namespace: namespace, kubectl: kubectl, only: [:validate_namespace_exists])
      assert_equal(["Namespace is not a valid Kubernetes namespace name"], validator.errors,
        "expected #{namespace.inspect} to be rejected")
    end
  end

  def test_valid_namespace_is_passed_to_kubectl
    kubectl = mock('kubectl')
    kubectl.expects(:run).with("get", "namespace", "-o", "name", "my-namespace-1",
      use_namespace: false, log_failure: false, attempts: 3).returns(["", "", stub(success?: true)])

    validator = build_validator(namespace: "my-namespace-1", kubectl: kubectl, only: [:validate_namespace_exists])

    assert_empty(validator.errors)
  end

  def test_context_that_would_be_parsed_as_a_kubectl_flag_is_rejected
    kubectl = mock('kubectl')
    kubectl.expects(:run).never

    validator = build_validator(context: "--kubeconfig=/tmp/evil", kubectl: kubectl,
      only: [:validate_context_exists_in_kubeconfig])

    assert_equal(["Context can not start with a dash"], validator.errors)
  end

  private

  def build_validator(kubectl:, only:, context: "test-context", namespace: "test-namespace")
    config = Krane::TaskConfig.new(context, namespace, logger)
    Krane::TaskConfigValidator.new(config, kubectl, mock('kubeclient_builder'), only: only)
  end
end
