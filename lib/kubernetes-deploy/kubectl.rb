# frozen_string_literal: true
require 'open3'

module KubernetesDeploy
  class Kubectl
    ERROR_MATCHERS = {
      not_found: /NotFound/,
      client_timeout: /Client\.Timeout exceeded while awaiting headers/,
    }
    DEFAULT_TIMEOUT = 15
    MAX_RETRY_DELAY = 16

    class ResourceNotFoundError < StandardError; end

    def initialize(namespace:, context:, logger:, log_failure_by_default:, default_timeout: DEFAULT_TIMEOUT,
      output_is_sensitive_default: false)
      @namespace = namespace
      @context = context
      @logger = logger
      @log_failure_by_default = log_failure_by_default
      @default_timeout = default_timeout
      @output_is_sensitive_default = output_is_sensitive_default

      raise ArgumentError, "namespace is required" if namespace.blank?
      raise ArgumentError, "context is required" if context.blank?
    end

    def run(*args, log_failure: nil, use_context: true, use_namespace: true, output: nil,
      raise_if_not_found: false, attempts: 1, output_is_sensitive: nil, retry_whitelist: nil)
      log_failure = @log_failure_by_default if log_failure.nil?
      output_is_sensitive = @output_is_sensitive_default if output_is_sensitive.nil?
      cmd = build_command_from_options(args, use_namespace, use_context, output)
      out, err, st = nil

      (1..attempts).to_a.each do |current_attempt|
        @logger.debug("Running command (attempt #{current_attempt}): #{cmd.join(' ')}")
        out, err, st = Open3.capture3(*cmd)
        @logger.debug("Kubectl out: " + out.gsub(/\s+/, ' ')) unless output_is_sensitive

        break if st.success?
        raise(ResourceNotFoundError, err) if err.match(ERROR_MATCHERS[:not_found]) && raise_if_not_found

        if log_failure
          warning = if current_attempt == attempts
            "The following command failed (attempt #{current_attempt}/#{attempts})"
          elsif retriable_err?(err, retry_whitelist)
            "The following command failed and will be retried (attempt #{current_attempt}/#{attempts})"
          else
            "The following command failed and cannot be retried"
          end
          @logger.warn("#{warning}: #{Shellwords.join(cmd)}")
          @logger.warn(err) unless output_is_sensitive
        else
          @logger.debug("Kubectl err: #{output_is_sensitive ? '<suppressed sensitive output>' : err}")
        end
        StatsD.increment('kubectl.error', 1, tags: { context: @context, namespace: @namespace, cmd: cmd[1] })

        break unless retriable_err?(err, retry_whitelist) && current_attempt < attempts
        sleep(retry_delay(current_attempt))
      end

      [out.chomp, err.chomp, st]
    end

    def retry_delay(attempt)
      # exponential backoff starting at 1s with cap at 16s, offset by up to 0.5s
      [2**(attempt - 1), MAX_RETRY_DELAY].min - Random.rand(0.5).round(1)
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

    def build_command_from_options(args, use_namespace, use_context, output)
      cmd = ["kubectl"] + args
      cmd.push("--namespace=#{@namespace}")              if use_namespace
      cmd.push("--context=#{@context}")                  if use_context
      cmd.push("--output=#{output}")                     if output
      cmd.push("--request-timeout=#{@default_timeout}")  if @default_timeout
      cmd
    end

    def retriable_err?(err, retry_whitelist)
      return !err.match(ERROR_MATCHERS[:not_found]) if retry_whitelist.nil?
      retry_whitelist.any? do |retriable|
        raise NotImplementedError, "No matcher defined for #{retriable.inspect}" unless ERROR_MATCHERS.key?(retriable)
        err.match(ERROR_MATCHERS[retriable])
      end
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
