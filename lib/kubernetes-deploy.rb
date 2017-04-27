# frozen_string_literal: true
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/hash/slice'
require 'active_support/core_ext/numeric/time'
require 'active_support/core_ext/string/inflections'
require 'active_support/core_ext/string/strip'

require 'kubernetes-deploy/logger'
require 'kubernetes-deploy/runner'

module KubernetesDeploy
  class FatalDeploymentError < StandardError; end

  class NamespaceNotFoundError < FatalDeploymentError
    def initialize(name, context)
      super("Namespace `#{name}` not found in context `#{context}`. Aborting the task.")
    end
  end

  include Logger
end
