module KubernetesDeploy
  class Validator
    attr_reader :errors

    def initialize(validation)
      @validation = validation
      @errors = {}
    end

    def validate!(args)
      validate_hash(args, @validation)
      @errors.empty?
    end

    def valid?
      @errors.empty?
    end

    private

    def validate_spec(spec, key, value)
      check_required(key, value, spec)
      check_type(key, value, spec)
      check_included(key, value, spec)

      sub_spec = spec[:spec]
      case sub_spec
      when Array
        validate_array(key, value, spec[:type], sub_spec) if value
      when Hash
        validate_hash(value, sub_spec) if value
      when nil
        # Nothing, we're done
      else
        raise "invalid spec #{sub_spec}"
      end
    end

    def validate_array(key, val, type, spec)
      raise 'Cannot provide a spec array if type is not Array' unless type == Array
      if val.is_a?(Array)
        val.each do |sub_val|
          validate_spec(spec.first, "#{key}.spec", sub_val)
        end
      end
    end

    def validate_hash(val, spec)
      spec.each do |sub_key, sub_spec|
        validate_spec(sub_spec, sub_key, val[sub_key.to_s])
      end
    end

    def check_required(key, value, spec)
      return true unless spec[:required] && value.nil?

      record_error(key, "was required")
      false
    end

    def check_type(key, value, spec)
      return true if !spec[:required] && value.nil?
      return true unless spec[:type]
      if spec[:type] == 'Boolean'
        return true unless !(value.is_a?(TrueClass) || value.is_a?(FalseClass) || value.nil?)
      else
        return true unless !(value.is_a?(spec[:type]) || value.nil?)
      end

      record_error(key, "supposed to be a #{spec[:type]} but was #{value.class}")
      false
    end

    def check_included(key, value, spec)
      return true if !spec[:required] && value.nil?
      return true unless spec[:included]
      return true if spec[:included].include?(value)

      value = 'empty' if value.nil?
      record_error(key, "must be one of #{spec[:included].join(', ')}, but was #{value}")
      false
    end

    def record_error(key, msg)
      @errors[key] ||= []
      @errors[key] << msg
    end
  end
end