# frozen_string_literal: true
require 'json'
require 'base64'
require 'open3'
require 'kubernetes-deploy/kubectl'

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

    def initialize(namespace:, context:, template_dir:, logger:)
      @namespace = namespace
      @context = context
      @ejson_file = "#{template_dir}/#{EJSON_SECRETS_FILE}"
      @logger = logger
      @kubectl = Kubectl.new(
        namespace: @namespace,
        context: @context,
        logger: @logger,
        log_failure_by_default: false,
        output_is_sensitive: true # output may contain ejson secrets
      )
    end

    def resources
      @resources ||= create_secrets
    end

    private

    def create_secrets
      return [] unless File.exist?(@ejson_file)
      with_decrypted_ejson do |decrypted|
        secrets = decrypted[MANAGED_SECRET_EJSON_KEY]
        unless secrets.present?
          @logger.warn("#{EJSON_SECRETS_FILE} does not have key #{MANAGED_SECRET_EJSON_KEY}."\
            "No secrets will be created.")
          return []
        end

        secrets.map do |secret_name, secret_spec|
          validate_secret_spec(secret_name, secret_spec)
          generate_secret_resource(secret_name, secret_spec["_type"], secret_spec["data"])
        end
      end
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

    def generate_secret_resource(secret_name, secret_type, data)
      unless data.is_a?(Hash) && data.values.all? { |v| v.is_a?(String) } # Secret data is map[string]string
        raise EjsonSecretError, "Data for secret #{secret_name} was invalid. Only key-value pairs are permitted."
      end
      encoded_data = data.each_with_object({}) do |(key, value), encoded|
        # Leading underscores in ejson keys are used to skip encryption of the associated value
        # To support this ejson feature, we need to exclude these leading underscores from the secret's keys
        secret_key = key.sub(/\A_/, '')
        encoded[secret_key] = Base64.strict_encode64(value)
      end

      secret = {
        'kind' => 'Secret',
        'apiVersion' => 'v1',
        'type' => secret_type,
        'metadata' => {
          "name" => secret_name,
          "labels" => { "name" => secret_name },
          "namespace" => @namespace,
          "annotations" => { MANAGEMENT_ANNOTATION => "true" },
        },
        "data" => encoded_data,
      }

      KubernetesDeploy::Secret.build(
        namespace: @namespace, context: @context, logger: @logger, definition: secret, statsd_tags: [],
      )
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
      @logger.info("Decrypting #{EJSON_SECRETS_FILE}")
      # ejson seems to dump both errors and output to STDOUT
      out_err, st = Open3.capture2e("EJSON_KEYDIR=#{key_dir} ejson decrypt #{@ejson_file}")
      raise EjsonSecretError, out_err unless st.success?
      JSON.parse(out_err)
    rescue JSON::ParserError => e
      raise EjsonSecretError, "Failed to parse decrypted ejson:\n  #{e}"
    end

    def fetch_private_key_from_secret
      @logger.info("Fetching ejson private key from secret #{EJSON_KEYS_SECRET}")

      secret = run_kubectl_json("get", "secret", EJSON_KEYS_SECRET)
      encoded_private_key = secret["data"][public_key]
      unless encoded_private_key
        raise EjsonSecretError, "Private key for #{public_key} not found in #{EJSON_KEYS_SECRET} secret"
      end

      Base64.decode64(encoded_private_key)
    end

    def run_kubectl_json(*args)
      args += ["--output=json"]
      out, err, st = @kubectl.run(*args)
      raise EjsonSecretError, err unless st.success?
      result = JSON.parse(out)
      result.fetch('items', result)
    end
  end
end
