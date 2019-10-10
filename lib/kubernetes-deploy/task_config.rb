# frozen_string_literal: true
module KubernetesDeploy
  class TaskConfig
    attr_reader :context, :namespace, :global_mode
    attr_accessor :namespace_definition

    def initialize(context, namespace, logger = nil, global_mode = false)
      @context = context
      @namespace = namespace
      @logger = logger
      @global_mode = global_mode
    end

    def logger
      @logger ||= KubernetesDeploy::FormattedLogger.build(@namespace, @context)
    end
  end
end
