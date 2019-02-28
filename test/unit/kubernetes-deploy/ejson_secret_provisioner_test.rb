# frozen_string_literal: true
require 'test_helper'

class EjsonSecretProvisionerTest < KubernetesDeploy::TestCase
  def test_resources_based_on_ejson_file_existence
    stub_kubectl_response("get", "secret", "ejson-keys", resp: dummy_ejson_secret)

    assert_empty(build_provisioner(fixture_path('hello-cloud')).resources)
    refute_empty(build_provisioner(fixture_path('ejson-cloud')).resources)
  end

  def test_run_with_secrets_file_invalid_json
    assert_raises_message(KubernetesDeploy::EjsonSecretError, /Failed to parse encrypted ejson/) do
      with_ejson_file("}") do |target_dir|
        build_provisioner(target_dir).resources
      end
    end
  end

  def test_resource_is_built_correctly
    stub_kubectl_response("get", "secret", "ejson-keys", resp: dummy_ejson_secret)

    resources = build_provisioner(fixture_path('ejson-cloud')).resources
    refute_empty(resources)

    secret = resources.find { |s| s.name == 'monitoring-token' }
    refute_nil(secret, "Expected secret not found")
    assert_equal(secret.class, KubernetesDeploy::Secret)
    assert_equal(secret.id, "Secret/monitoring-token")
  end

  def test_run_with_ejson_keypair_mismatch
    wrong_public = {
      "2200e55f22dd0c93fac3832ba14842cc75fa5a99a2e01696daa30e188d465036" =>
        "139d5c2a30901dd8ae186be582ccc0a882c16f8e0bb5429884dbc7296e80669e",
    }
    stub_kubectl_response("get", "secret", "ejson-keys", resp: dummy_ejson_secret(wrong_public))

    msg = "Private key for #{fixture_public_key} not found"
    assert_raises_message(KubernetesDeploy::EjsonSecretError, msg) do
      build_provisioner.resources
    end
  end

  def test_run_with_bad_private_key_in_cloud_keys
    wrong_private = { fixture_public_key => "139d5c2a30901dd8ae186be582ccc0a882c16f8e0bb5429884dbc7296e80669e" }
    stub_kubectl_response("get", "secret", "ejson-keys", resp: dummy_ejson_secret(wrong_private))

    assert_raises_message(KubernetesDeploy::EjsonSecretError, /Decryption failed/) do
      build_provisioner.resources
    end
  end

  def test_run_with_cloud_keys_secret_missing
    realistic_err = "Error from server (NotFound): secrets \"ejson-keys\" not found"
    stub_kubectl_response("get", "secret", "ejson-keys", resp: "", err: realistic_err, success: false)
    assert_raises_message(KubernetesDeploy::EjsonSecretError, /secrets "ejson-keys" not found/) do
      build_provisioner.resources
    end
  end

  def test_run_with_file_missing_section_for_ejson_secrets_logs_warning
    stub_kubectl_response("get", "secret", "ejson-keys", resp: dummy_ejson_secret)
    new_content = { "_public_key" => fixture_public_key, "not_the_right_key" => [] }

    with_ejson_file(new_content.to_json) do |target_dir|
      build_provisioner(target_dir).resources
    end
    assert_logs_match("No secrets will be created.")
  end

  def test_run_with_incomplete_secret_spec
    stub_kubectl_response("get", "secret", "ejson-keys", resp: dummy_ejson_secret)
    new_content = {
      "_public_key" => fixture_public_key,
      "kubernetes_secrets" => { "foobar" => {} },
    }

    msg = "Ejson incomplete for secret foobar: secret type unspecified, no data provided"
    assert_raises_message(KubernetesDeploy::EjsonSecretError, msg) do
      with_ejson_file(new_content.to_json) do |target_dir|
        build_provisioner(target_dir).resources
      end
    end
  end

  private

  def correct_ejson_key_secret_data
    {
      fixture_public_key => "fedcc95132e9b399ee1f404364fdbc81bdbe4feb5b8292b061f1022481157d5a",
    }
  end

  def fixture_public_key
    "65f79806388144edf800bf9fa683c98d3bc9484768448a275a35d398729c892a"
  end

  def with_ejson_file(content)
    Dir.mktmpdir do |target_dir|
      File.write(File.join(target_dir, KubernetesDeploy::EjsonSecretProvisioner::EJSON_SECRETS_FILE), content)
      yield target_dir
    end
  end

  def dummy_ejson_secret(data = correct_ejson_key_secret_data)
    dummy_secret_hash(data: data, name: 'ejson-keys', ejson: false)
  end

  def dummy_secret_hash(name: SecureRandom.hex(4), data: {}, ejson: true)
    encoded_data = data.each_with_object({}) do |(key, value), encoded|
      encoded[key] = Base64.strict_encode64(value)
    end

    secret = {
      'kind' => 'Secret',
      'apiVersion' => 'v1',
      'type' => 'Opaque',
      'metadata' => {
        "name" => name,
        "labels" => { "name" => name },
        "namespace" => 'test',
      },
      "data" => encoded_data,
    }
    if ejson
      secret['metadata']['annotations'] = { KubernetesDeploy::EjsonSecretProvisioner::EJSON_SECRET_ANNOTATION => true }
    end
    secret
  end

  def build_provisioner(dir = nil)
    dir ||= fixture_path('ejson-cloud')
    KubernetesDeploy::EjsonSecretProvisioner.new(
      namespace: 'test',
      context: KubeclientHelper::TEST_CONTEXT,
      template_dir: dir,
      logger: logger,
      statsd_tags: []
    )
  end
end
