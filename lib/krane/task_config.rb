# frozen_string_literal: true
module Krane
  class TaskConfig
    attr_reader :context, :namespace

    def initialize(context, namespace, logger = nil)
      @context = context
      @namespace = namespace
      @logger = logger
    end

    def logger
      @logger ||= Krane::FormattedLogger.build(@namespace, @context)
    end
  end
end
