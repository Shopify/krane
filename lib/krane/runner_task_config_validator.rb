# frozen_string_literal: true
module Krane
  class RunnerTaskConfigValidator < TaskConfigValidator
    def initialize(template, *arguments)
      super(*arguments)
      @template = template
      @validations += %i(validate_template)
    end

    private

    def validate_template
      if @template.blank?
        @errors << "Task template name can't be nil"
      end
    end
  end
end
