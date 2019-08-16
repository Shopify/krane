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

    def kubectl(log_failure_by_default: true)
      @kubectl ||= Kubectl.new(
        namespace: @namespace,
        context: @context,
        logger: logger,
        log_failure_by_default: log_failure_by_default
      )
    end

    def kubeclient_builder
      @kubeclient ||= KubeclientBuilder.new
    end
  end
end
