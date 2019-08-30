# frozen_string_literal: true
require 'test_helper'
require 'kubernetes-deploy/kubeclient_builder'

class KubeClientBuilderTest < KubernetesDeploy::TestCase
  def test_config_validation_default_config_file
    builder = KubernetesDeploy::KubeclientBuilder.new(kubeconfig: nil)
    assert_equal(builder.validate_config_files, [])
  end

  def test_config_validation_missing_file
    config_file = File.join(__dir__, '../../fixtures/kube-config/unknown_config.yml')
    builder = KubernetesDeploy::KubeclientBuilder.new(kubeconfig: config_file)
    errors = builder.validate_config_files
    assert_equal(1, errors.length)
    assert_equal(errors.first, "Kubeconfig not found at #{config_file}")
  end

  def test_build_runs_config_validation
    config_file = File.join(__dir__, '../../fixtures/kube-config/unknown_config.yml')
    kubeclient_builder = KubernetesDeploy::KubeclientBuilder.new(kubeconfig: config_file)

    expected_err = /Kubeconfig not found at .*unknown_config.yml/
    assert_raises_message(KubernetesDeploy::TaskConfigurationError, expected_err) do
      kubeclient_builder.build_v1_kubeclient('test-context')
    end
  end

  def test_no_config_files_specified
    builder = KubernetesDeploy::KubeclientBuilder.new(kubeconfig: " : ")
    errors = builder.validate_config_files
    assert_equal(1, errors.length)
    assert_equal(errors.first, "Kubeconfig file name(s) not set in $KUBECONFIG")

    builder = KubernetesDeploy::KubeclientBuilder.new(kubeconfig: "")
    errors = builder.validate_config_files
    assert_equal(1, errors.length)
    assert_equal(errors.first, "Kubeconfig file name(s) not set in $KUBECONFIG")
  end

  def test_multiple_valid_configuration_files
    default_config = "#{Dir.home}/.kube/config"
    extra_config = File.join(__dir__, '../../fixtures/kube-config/dummy_config.yml')
    builder = KubernetesDeploy::KubeclientBuilder.new(kubeconfig: "#{default_config}:#{extra_config}")
    assert_empty(builder.validate_config_files)
  end

  def test_build_client_from_multiple_config_files
    Kubeclient::Client.any_instance.stubs(:discover)
    default_config = "#{Dir.home}/.kube/config"
    dummy_config = File.join(__dir__, '../../fixtures/kube-config/dummy_config.yml')

    kubeclient_builder = KubernetesDeploy::KubeclientBuilder.new(kubeconfig: "#{default_config}:#{dummy_config}")
    # Build kubeclient for an unknown context fails
    context_name = "unknown_context"
    assert_raises_message(KubernetesDeploy::KubeclientBuilder::ContextMissingError,
      "`#{context_name}` context must be configured in your KUBECONFIG file(s) " \
      "(#{default_config}, #{dummy_config})") do
      kubeclient_builder.build_v1_kubeclient(context_name)
    end
    # Build kubeclient for a context present in the dummy config succeeds
    context_name = "docker-for-desktop"
    client = kubeclient_builder.build_v1_kubeclient(context_name)
    assert(!client.nil?, "Expected Kubeclient is built for context " \
      "#{context_name} with success.")
  end
end
