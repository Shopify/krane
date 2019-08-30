# frozen_string_literal: true
module KubernetesDeploy
  class TaskConfig
    attr_reader :context, :namespace

    def initialize(context, namespace, logger = nil)
      @context = context
      @namespace = namespace
      @logger = logger
    end

    def logger
      @logger ||= KubernetesDeploy::FormattedLogger.build(@namespace, @context)
    end
  end
end
