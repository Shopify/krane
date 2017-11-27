# frozen_string_literal: true

module KubernetesDeploy
  class Kubectl
    def initialize(namespace:, context:, logger:, log_failure_by_default:, default_timeout: '30s',
      output_is_sensitive: false)
      @namespace = namespace
      @context = context
      @logger = logger
      @log_failure_by_default = log_failure_by_default
      @default_timeout = default_timeout
      @output_is_sensitive = output_is_sensitive

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
      @logger.debug(out.shellescape) unless output_is_sensitive?

      if !st.success? && log_failure
        @logger.warn("The following command failed: #{Shellwords.join(args)}")
        @logger.warn(err) unless output_is_sensitive?
      end
      [out.chomp, err.chomp, st]
    end

    def version_info
      @version_info ||=
        begin
          response, _, status = run("version", use_namespace: false, log_failure: true)
          raise KubectlError, "Could not retrieve kubectl version info" unless status.success?
          extract_version_info_from_kubectl_response(response)
        end
    end

    def client_version
      version_info[:client]
    end

    def server_version
      version_info[:server]
    end

    private

    def output_is_sensitive?
      @output_is_sensitive
    end

    def extract_version_info_from_kubectl_response(response)
      info = {}
      response.each_line do |l|
        match = l.match(/^(?<kind>Client|Server).* GitVersion:"v(?<version>\d+\.\d+\.\d+)/)
        if match
          info[match[:kind].downcase.to_sym] = Gem::Version.new(match[:version])
        end
      end
      info
    end
  end
end
