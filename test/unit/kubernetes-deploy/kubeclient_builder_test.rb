# frozen_string_literal: true
require 'test_helper'
require 'kubernetes-deploy/kubeclient_builder'

class KubeClientBuilderTest < KubernetesDeploy::TestCase
  include KubernetesDeploy::KubeclientBuilder

  def setup
    Kubeclient::Client.any_instance.stubs(:discover)
    super
  end

  def test_build_client_from_multiple_config_files
    old_config = ENV['KUBECONFIG']
    # Set KUBECONFIG to include multiple config files
    valid_config = File.join(__dir__, '../../fixtures/kube-config/valid_config.yml')
    ENV['KUBECONFIG'] = "#{old_config}:#{valid_config}"
    # Build kubeclient for an unknown context fails
    context_name = "unknown_context"
    assert_raises_message(ContextMissingError,
      "`#{context_name}` context must be configured in your KUBECONFIG file(s) " \
      "(#{ENV['KUBECONFIG']}).") do
      build_v1_kubeclient(context_name)
    end
    # Build kubeclient for an existing context success
    context_name = KubeclientHelper::MINIKUBE_CONTEXT
    client = build_v1_kubeclient(context_name)
    assert !client.nil?, "Expected Kubeclient is built for context " \
    	"#{context_name} with success."
  ensure
    ENV['KUBECONFIG'] = old_config
  end
end
