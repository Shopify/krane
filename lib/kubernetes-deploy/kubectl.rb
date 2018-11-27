# frozen_string_literal: true

module KubernetesDeploy
  class Kubectl
    DEFAULT_TIMEOUT = 15
    NOT_FOUND_ERROR_TEXT = 'NotFound'

    class ResourceNotFoundError < StandardError; end

    def initialize(namespace:, context:, logger:, log_failure_by_default:, default_timeout: DEFAULT_TIMEOUT,
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

    def run(*args, log_failure: nil, use_context: true, use_namespace: true, raise_if_not_found: false, attempts: 1)
      log_failure = @log_failure_by_default if log_failure.nil?

      args = args.unshift("kubectl")
      args.push("--namespace=#{@namespace}") if use_namespace
      args.push("--context=#{@context}")     if use_context
      args.push("--request-timeout=#{@default_timeout}") if @default_timeout
      out, err, st = nil

      (1..attempts).to_a.each do |attempt|
        @logger.debug "Running command (attempt #{attempt}): #{args.join(' ')}"
        out, err, st = Open3.capture3(*args)
        @logger.debug("Kubectl out: " + out.gsub(/\s+/, ' ')) unless output_is_sensitive?

        break if st.success?

        if log_failure
          @logger.warn("The following command failed (attempt #{attempt}/#{attempts}): #{Shellwords.join(args)}")
          @logger.warn(err) unless output_is_sensitive?
        end

        if err.match(NOT_FOUND_ERROR_TEXT)
          raise(ResourceNotFoundError, err) if raise_if_not_found
        else
          @logger.debug("Kubectl err: #{err}") unless output_is_sensitive?
          StatsD.increment('kubectl.error', 1, tags: { context: @context, namespace: @namespace, cmd: args[1] }, prefix: "KubernetesDeploy")
        end
        sleep retry_delay(attempt) unless attempt == attempts
      end

      [out.chomp, err.chomp, st]
    end

    def retry_delay(attempt)
      attempt
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
