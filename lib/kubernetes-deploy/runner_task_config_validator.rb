# frozen_string_literal: true
module KubernetesDeploy
  class RunnerTaskConfigValidator < TaskConfigValidator
    def initialize(template, args, *arguments)
      super(*arguments)
      @template = template
      @args = args
      @validations += %i(validate_template validate_args)
    end

    private

    def validate_args
      if @args.blank?
        @errors << "Args can't be nil"
      end
    end

    def validate_template
      if @template.blank?
        @errors << "Task template name can't be nil"
      end
    end
  end
end
