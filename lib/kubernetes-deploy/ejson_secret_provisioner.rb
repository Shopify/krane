# frozen_string_literal: true
require 'json'
require 'base64'
require 'open3'
require 'kubernetes-deploy/logger'

module KubernetesDeploy
  class EjsonSecretError < FatalDeploymentError
    def initialize(msg)
      super("Creation of Kubernetes secrets from ejson failed: #{msg}")
    end
  end

  class EjsonSecretProvisioner
    MANAGEMENT_ANNOTATION = "kubernetes-deploy.shopify.io/ejson-secret"
    MANAGED_SECRET_EJSON_KEY = "kubernetes_secrets"
    EJSON_SECRETS_FILE = "secrets.ejson"
    EJSON_KEYS_SECRET = "ejson-keys"

    def initialize(namespace:, template_dir:, client:)
      @namespace = namespace
      @ejson_file = "#{template_dir}/#{EJSON_SECRETS_FILE}"
      @kubeclient = client
    end

    def secret_changes_required?
      File.exist?(@ejson_file) || managed_secrets_exist?
    end

    def run
      create_secrets
      prune_managed_secrets
    end

    private

    def create_secrets
      with_decrypted_ejson do |decrypted|
        secrets = decrypted[MANAGED_SECRET_EJSON_KEY]
        unless secrets.present?
          KubernetesDeploy.logger.warn("#{EJSON_SECRETS_FILE} does not have key #{MANAGED_SECRET_EJSON_KEY}."\
            "No secrets will be created.")
          return
        end

        secrets.each do |secret_name, secret_spec|
          validate_secret_spec(secret_name, secret_spec)
          create_or_update_secret(secret_name, secret_spec["_type"], secret_spec["data"])
        end
      end
    end

    def prune_managed_secrets
      ejson_secret_names = encrypted_ejson.fetch(MANAGED_SECRET_EJSON_KEY, {}).keys
      live_secrets = @kubeclient.get_secrets(namespace: @namespace)

      live_secrets.each do |secret|
        secret_name = secret.metadata.name
        next unless secret_managed?(secret)
        next if ejson_secret_names.include?(secret_name)

        KubernetesDeploy.logger.info("Pruning secret #{secret_name}")
        @kubeclient.delete_secret(secret_name, @namespace)
      end
    end

    def managed_secrets_exist?
      all_secrets = @kubeclient.get_secrets(namespace: @namespace)
      all_secrets.any? { |secret| secret_managed?(secret) }
    end

    def secret_managed?(secret)
      secret.metadata.annotations.to_h.stringify_keys.key?(MANAGEMENT_ANNOTATION)
    end

    def encrypted_ejson
      @encrypted_ejson ||= load_ejson_from_file
    end

    def public_key
      encrypted_ejson["_public_key"]
    end

    def private_key
      @private_key ||= fetch_private_key_from_secret
    end

    def validate_secret_spec(secret_name, spec)
      errors = []
      errors << "secret type unspecified" if spec["_type"].blank?
      errors << "no data provided" if spec["data"].blank?

      unless errors.empty?
        raise EjsonSecretError, "Ejson incomplete for secret #{secret_name}: #{errors.join(', ')}"
      end
    end

    def create_or_update_secret(secret_name, secret_type, data)
      metadata = {
        name: secret_name,
        labels: { "name" => secret_name },
        namespace: @namespace,
        annotations: { MANAGEMENT_ANNOTATION => "true" }
      }
      secret = Kubeclient::Secret.new(type: secret_type, stringData: data, metadata: metadata)
      if secret_exists?(secret)
        KubernetesDeploy.logger.info("Updating secret #{secret_name}")
        @kubeclient.update_secret(secret)
      else
        KubernetesDeploy.logger.info("Creating secret #{secret_name}")
        @kubeclient.create_secret(secret)
      end
    rescue KubeException => e
      raise unless e.error_code == 400
      raise EjsonSecretError, "Data for secret #{secret_name} was invalid: #{e}"
    end

    def secret_exists?(secret)
      @kubeclient.get_secret(secret.metadata.name, @namespace)
      true
    rescue KubeException => error
      raise unless error.error_code == 404
      false
    end

    def load_ejson_from_file
      return {} unless File.exist?(@ejson_file)
      JSON.parse(File.read(@ejson_file))
    rescue JSON::ParserError => e
      raise EjsonSecretError, "Failed to parse encrypted ejson:\n  #{e}"
    end

    def with_decrypted_ejson
      return unless File.exist?(@ejson_file)

      Dir.mktmpdir("ejson_keydir") do |key_dir|
        File.write(File.join(key_dir, public_key), private_key)
        decrypted = decrypt_ejson(key_dir)
        yield decrypted
      end
    end

    def decrypt_ejson(key_dir)
      KubernetesDeploy.logger.info("Decrypting #{EJSON_SECRETS_FILE}")
      # ejson seems to dump both errors and output to STDOUT
      out_err, st = Open3.capture2e("EJSON_KEYDIR=#{key_dir} ejson decrypt #{@ejson_file}")
      raise EjsonSecretError, out_err unless st.success?
      JSON.parse(out_err)
    rescue JSON::ParserError => e
      raise EjsonSecretError, "Failed to parse decrypted ejson:\n  #{e}"
    end

    def fetch_private_key_from_secret
      KubernetesDeploy.logger.info("Fetching ejson private key from secret #{EJSON_KEYS_SECRET}")
      secret = @kubeclient.get_secret(EJSON_KEYS_SECRET, @namespace)
      encoded_private_key = secret["data"][public_key]
      unless encoded_private_key
        raise EjsonSecretError, "Private key for #{public_key} not found in #{EJSON_KEYS_SECRET} secret"
      end

      Base64.decode64(encoded_private_key)
    rescue KubeException => error
      raise unless error.error_code == 404
      secret_missing_err = "Failed to decrypt ejson: secret #{EJSON_KEYS_SECRET} not found in namespace #{@namespace}."
      raise EjsonSecretError, secret_missing_err
    end
  end
end
