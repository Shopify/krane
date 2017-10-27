# frozen_string_literal: true

module KubernetesDeploy
  class Kubectl
    def initialize(namespace:, context:, logger:, log_failure_by_default:, default_timeout: '30s')
      @namespace = namespace
      @context = context
      @logger = logger
      @log_failure_by_default = log_failure_by_default
      @default_timeout = default_timeout

      raise ArgumentError, "namespace is required" if namespace.blank?
      raise ArgumentError, "context is required" if context.blank?
    end

    def run(*args, log_failure: nil, use_context: true, use_namespace: true)
      log_failure = @log_failure_by_default if log_failure.nil?

      args = args.unshift("kubectl")
      args.push("--namespace=#{@namespace}") if use_namespace
      args.push("--context=#{@context}")     if use_context
      args.push("--request-timeout=#{@default_timeout}") if @default_timeout

      @logger.debug Shellwords.join(args)
      out, err, st = Open3.capture3(*args)
      @logger.debug(out.shellescape)

      if !st.success? && log_failure
        @logger.warn("The following command failed: #{Shellwords.join(args)}")
        @logger.warn(err)
      end
      [out.chomp, err.chomp, st]
    end
  end
end
