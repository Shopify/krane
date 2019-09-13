# frozen_string_literal: true
module KubernetesDeploy
  class RunnerTaskConfigValidator < TaskConfigValidator
    attr_accessor :template, :args

    def initialize(*args)
      super
      @validations += %i(validate_template validate_args)
    end

    private

    def validate_args
      if args.blank?
        @errors << "Args can't be nil"
      end
    end

    def validate_template
      if template.blank?
        @errors << "Task template name can't be nil"
      end
    end
  end
end
