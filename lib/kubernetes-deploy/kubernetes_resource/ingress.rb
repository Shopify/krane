# frozen_string_literal: true
module KubernetesDeploy
  class Ingress < KubernetesResource
    TIMEOUT = 30.seconds

    def sync
      _, _err, st = kubectl.run("get", type, @name)
      @status = st.success? ? "Created" : "Unknown"
      @found = st.success?
    end

    def deploy_succeeded?
      exists?
    end

    def deploy_failed?
      false
    end

    def exists?
      @found
    end

    def validate_definition
      validator = KubernetesDeploy::Validator.new(ingress_validation_spec)
      result = super && validator.validate!
      if validator.errors
        if @validation_error_msg
          @validation_error_msg << validator.errors
        else
          @validation_error_msg = validator.errors
        end
      end
      result
    end

    private

    def ingress_validation_spec
      {
        metadata: {
          type: Hash,
          required: true,
          spec: {
            annotations: {
              type: Array,
              required: true,
              spec: {
                'kubernetes.io/ingress.class' => {
                  type: String,
                  required: true,
                  included: %w(nginx gce)
                }
              }
            }
          }
        }
      }
    end
  end
end
