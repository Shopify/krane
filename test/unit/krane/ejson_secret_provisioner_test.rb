# frozen_string_literal: true
require 'test_helper'

class EjsonSecretProvisionerTest < Krane::TestCase
  def test_resources_based_on_ejson_file_existence
    stub_server_dry_run_version_request(attempts: 2)
    stub_server_dry_run_validation_request.times(3) # there are three secrets in the ejson

    assert_empty(build_provisioner(fixture_path('hello-cloud')).resources)
    refute_empty(build_provisioner(fixture_path('ejson-cloud')).resources)
  end

  def test_run_with_secrets_file_invalid_json
    assert_raises_message(Krane::EjsonSecretError, /Failed to parse encrypted ejson/) do
      with_ejson_file("}") do |target_dir|
        build_provisioner(target_dir).resources
      end
    end
  end

  def test_resource_is_built_correctly
    stub_server_dry_run_version_request(attempts: 2)
    stub_server_dry_run_validation_request.times(3) # there are three secrets in the ejson
    resources = build_provisioner(fixture_path('ejson-cloud')).resources
    refute_empty(resources)
    secret = resources.find { |s| s.name == 'monitoring-token' }
    refute_nil(secret, "Expected secret not found")
    assert_equal(secret.class, Krane::Secret)
    assert_equal(secret.id, "Secret/monitoring-token")
  end

  def test_run_with_ejson_keypair_mismatch
    wrong_public = {
      "2200e55f22dd0c93fac3832ba14842cc75fa5a99a2e01696daa30e188d465036" =>
        "139d5c2a30901dd8ae186be582ccc0a882c16f8e0bb5429884dbc7296e80669e",
    }

    msg = "Private key for #{fixture_public_key} not found"
    assert_raises_message(Krane::EjsonSecretError, msg) do
      build_provisioner(ejson_keys_secret: dummy_ejson_secret(wrong_public)).resources
    end
  end

  def test_run_with_bad_private_key_in_cloud_keys
    wrong_private = { fixture_public_key => "139d5c2a30901dd8ae186be582ccc0a882c16f8e0bb5429884dbc7296e80669e" }
    assert_raises_message(Krane::EjsonSecretError, /Decryption failed/) do
      build_provisioner(ejson_keys_secret: dummy_ejson_secret(wrong_private)).resources
    end
  end

  def test_decryption_failure_with_error_on_stdout_reports_error
    # ejson < 1.2 prints errors on stdout
    Open3.expects(:capture3).with(instance_of(Hash), 'ejson', 'decrypt', instance_of(String))
      .returns(["Some error from ejson", "", stub(success?: false)])
    msg = "Generation of Kubernetes secrets from ejson failed: Some error from ejson"
    assert_raises_message(Krane::EjsonSecretError, msg) do
      build_provisioner(fixture_path('ejson-cloud')).resources
    end
  end

  def test_decryption_successful_but_warning_on_stderr_does_not_confuse_us
    valid_response = {
      "_public_key" => fixture_public_key,
      "kubernetes_secrets" =>
        {
          "test" => {
            "_type" => "Opaque",
            "data" => { "test" => "true" },
          },
        },
    }.to_json

    Open3.expects(:capture3).with(instance_of(Hash), 'ejson', 'decrypt', instance_of(String))
      .returns([valid_response, "Permissions warning!", stub(success?: true)])
    stub_server_dry_run_version_request(attempts: 2)
    stub_server_dry_run_validation_request

    resources = build_provisioner(fixture_path('ejson-cloud')).resources
    refute_empty(resources)
  end

  def test_no_ejson_keys_secret_provided
    assert_raises_message(Krane::EjsonSecretError,
      /Generation of Kubernetes secrets from ejson failed: Secret ejson-keys not provided, cannot decrypt secrets/) do
      build_provisioner(ejson_keys_secret: nil).resources
    end
  end

  def test_run_with_file_missing_section_for_ejson_secrets_logs_warning
    new_content = { "_public_key" => fixture_public_key, "not_the_right_key" => [] }

    with_ejson_file(new_content.to_json) do |target_dir|
      build_provisioner(target_dir).resources
    end
    assert_logs_match("No secrets will be created.")
  end

  def test_run_with_incomplete_secret_spec
    new_content = {
      "_public_key" => fixture_public_key,
      "kubernetes_secrets" => { "foobar" => {} },
    }

    msg = "Ejson incomplete for secret foobar: secret type unspecified, no data provided"
    assert_raises_message(Krane::EjsonSecretError, msg) do
      with_ejson_file(new_content.to_json) do |target_dir|
        build_provisioner(target_dir).resources
      end
    end
  end

  def test_proactively_validates_resulting_resources_and_raises_without_logging
    stub_server_dry_run_version_request(attempts: 2)
    stub_server_dry_run_validation_request
    Krane::Secret.any_instance.expects(:validation_failed?).returns(true)
    msg = "Generation of Kubernetes secrets from ejson failed: Resulting resource Secret/catphotoscom failed validation"
    assert_raises_message(Krane::EjsonSecretError, msg) do
      build_provisioner(fixture_path('ejson-cloud')).resources
    end
    refute_logs_match("Secret")
  end

  def test_run_with_selector_does_not_raise_exception
    stub_server_dry_run_version_request(attempts: 2)
    stub_server_dry_run_validation_request.times(3) # there are three secrets in the ejson
    provisioner = build_provisioner(
      fixture_path('ejson-cloud'),
      selector: Krane::LabelSelector.new("app" => "yay")
    )
    refute_empty(provisioner.resources)
  end

  private

  def stub_server_dry_run_validation_request(attempts: 3)
    stub_kubectl_response("apply", "-f", anything, "--dry-run=server", "--output=name",
      resp: dummy_secret_hash, json: false,
      kwargs: {
        log_failure: false,
        output_is_sensitive: true,
        retry_whitelist: [:client_timeout, :empty, :context_deadline],
        attempts: attempts,
      })
  end

  def stub_server_dry_run_version_request(attempts: 1)
    stub_kubectl_response("version",
      resp: dummy_version,
        kwargs: {
          use_namespace: false,
          log_failure: true,
          attempts: attempts,
        })
  end

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
      File.write(File.join(target_dir, Krane::EjsonSecretProvisioner::EJSON_SECRETS_FILE), content)
      yield target_dir
    end
  end

  def dummy_ejson_secret(data = correct_ejson_key_secret_data)
    dummy_secret_hash(data: data, name: 'ejson-keys')
  end

  def dummy_secret_hash(name: SecureRandom.hex(4), data: {})
    encoded_data = data.each_with_object({}) do |(key, value), encoded|
      encoded[key] = Base64.strict_encode64(value)
    end

    {
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
  end

  def dummy_version
    {
      "clientVersion": {
        "major": "1",
        "minor": "23",
        "gitVersion": "v1.23.1",
        "gitCommit": "86ec240af8cbd1b60bcc4c03c20da9b98005b92e",
        "gitTreeState": "clean",
        "buildDate": "2021-12-16T11:33:37Z",
        "goVersion": "go1.17.5",
        "compiler": "gc",
        "platform": "darwin/arm64"
      },
      "serverVersion": {
        "major": "1",
        "minor": "23",
        "gitVersion": "v1.23.4",
        "gitCommit": "e6c093d87ea4cbb530a7b2ae91e54c0842d8308a",
        "gitTreeState": "clean",
        "buildDate": "2022-03-06T21:39:59Z",
        "goVersion": "go1.17.7",
        "compiler": "gc",
        "platform": "linux/arm64"
      }
    }
  end

  def build_provisioner(dir = nil, selector: nil, ejson_keys_secret: dummy_ejson_secret)
    dir ||= fixture_path('ejson-cloud')
    Krane::EjsonSecretProvisioner.new(
      task_config: task_config(namespace: 'test'),
      ejson_keys_secret: ejson_keys_secret,
      ejson_file: File.expand_path(File.join(dir, Krane::EjsonSecretProvisioner::EJSON_SECRETS_FILE)),
      statsd_tags: [],
      selector: selector,
    )
  end
end
