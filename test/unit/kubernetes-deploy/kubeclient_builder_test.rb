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
    # Set KUBECONFIG to include multiple config files
    dummy_config = File.join(__dir__, '../../fixtures/kube-config/dummy_config.yml')
    @kubeconfig = "#{ENV['KUBECONFIG']}:#{dummy_config}"
    # Build kubeclient for an unknown context fails
    context_name = "unknown_context"
    assert_raises_message(ContextMissingError,
      "`#{context_name}` context must be configured in your KUBECONFIG file(s) " \
      "(#{ENV['KUBECONFIG']}).") do
      build_v1_kubeclient(context_name)
    end
    # Build kubeclient for a context present in the dummy config succeeds
    context_name = "docker-for-desktop"
    client = build_v1_kubeclient(context_name)
    assert(!client.nil?, "Expected Kubeclient is built for context " \
    	"#{context_name} with success.")
  end

  def kubeconfig
    @kubeconfig || ENV["KUBECONFIG"]
  end
end
