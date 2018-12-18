# frozen_string_literal: true
require 'test_helper'

class GoogleFriendlyConfigTest < KubernetesDeploy::TestCase
  def setup
    WebMock.disable_net_connect!
    set_google_env_vars
  end

  def teardown
    WebMock.allow_net_connect!
  end

  def test_auth_use_default_gcp_success
    config = KubernetesDeploy::KubeclientBuilder::GoogleFriendlyConfig.new(kubeconfig, "")

    stub_request(:post, 'https://oauth2.googleapis.com/token')
      .to_return(
        headers: { 'Content-Type' => 'application/json' },
        body: {
          "access_token" => "bearer_token",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "id_token" => "identity_token",
        }.to_json,
        status: 200
      )

    context = config.context("google")
    assert_equal('bearer_token', context.auth_options[:bearer_token])
  end

  def test_auth_use_default_gcp_failure
    config = KubernetesDeploy::KubeclientBuilder::GoogleFriendlyConfig.new(kubeconfig, "")

    stub_request(:post, 'https://oauth2.googleapis.com/token')
      .to_return(
        headers: { 'Content-Type' => 'application/json' },
        body: '',
        status: 401
      )

    assert_raises(KubeException) do
      config.context("google")
    end
  end

  def test_non_google_auth_works
    config = KubernetesDeploy::KubeclientBuilder::GoogleFriendlyConfig.new(kubeconfig, "")

    context = config.context("minikube")

    assert_equal('test', context.auth_options[:password])
    assert_equal('admin', context.auth_options[:username])
  end

  def kubeconfig
    {
      'apiVersion' => 'v1',
      'clusters' => [
        { 'cluster' => { 'server' => 'https://192.168.64.3:8443' }, 'name' => 'test' },
      ],
      'contexts' => [
        {
          'context' => {
            'cluster' => 'test',
            'user' => 'google',
          },
          'name' => 'google',
        },
        {
          'context' => {
            'cluster' => 'test', 'user' => 'minikube'
          },
          'name' => 'minikube',
        },
      ],
      'users' => [
        {
          'name' => 'google',
          'user' => {
            'auth-provider' => {
              'name' => 'gcp',
              'config' => { 'access_token' => 'test' },
            },
          },
        },
        {
          'name' => 'minikube',
          'user' => {
            'password' => 'test',
            'username' => 'admin',
          },
        },
      ],
    }.stringify_keys
  end

  def set_google_env_vars
    ENV["GOOGLE_PRIVATE_KEY"] ||= "FAKE"
    ENV["GOOGLE_CLIENT_EMAIL"] ||= "fake@email.com"
    ENV["GOOGLE_ACCOUNT_TYPE"] ||= 'authorized_user'
    ENV["GOOGLE_CLIENT_ID"] ||= 'fake'
    ENV["GOOGLE_CLIENT_SECRET"] ||= 'fake'
    ENV["REFRESH_TOKEN_VAR"] ||= 'fake'
  end
end
