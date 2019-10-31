# frozen_string_literal: true

require 'krane/task_config_validator'

module Krane
  class GlobalDeployTaskConfigValidator < Krane::TaskConfigValidator
    def initialize(*arguments)
      super(*arguments)
      @validations -= [:validate_namespace_exists]
    end
  end
end
