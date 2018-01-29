# frozen_string_literal: true
require 'json'
require 'open3'
require 'shellwords'
require 'kubernetes-deploy/kubectl'
require 'kubernetes-deploy/utils'

module KubernetesDeploy
  class KubernetesResource
    attr_reader :name, :namespace, :context
    attr_writer :type, :deploy_started_at

    TIMEOUT = 5.minutes
    LOG_LINE_COUNT = 250

    DISABLE_FETCHING_LOG_INFO = 'DISABLE_FETCHING_LOG_INFO'
    DISABLE_FETCHING_EVENT_INFO = 'DISABLE_FETCHING_EVENT_INFO'
    DISABLED_LOG_INFO_MESSAGE = "collection is disabled by the #{DISABLE_FETCHING_LOG_INFO} env var."
    DISABLED_EVENT_INFO_MESSAGE = "collection is disabled by the #{DISABLE_FETCHING_EVENT_INFO} env var."
    DEBUG_RESOURCE_NOT_FOUND_MESSAGE = "None found. Please check your usual logging service (e.g. Splunk)."
    UNUSUAL_FAILURE_MESSAGE = <<~MSG
      It is very unusual for this resource type to fail to deploy. Please try the deploy again.
      If that new deploy also fails, contact your cluster administrator.
      MSG
    STANDARD_TIMEOUT_MESSAGE = <<~MSG
      Kubernetes will continue to attempt to deploy this resource in the cluster, but at this point it is considered unlikely that it will succeed.
      If you have reason to believe it will succeed, retry the deploy to continue to monitor the rollout.
      MSG

    TIMEOUT_OVERRIDE_ANNOTATION = "kubernetes-deploy.shopify.io/timeout-override"

    def self.build(namespace:, context:, definition:, logger:)
      opts = { namespace: namespace, context: context, definition: definition, logger: logger }
      if KubernetesDeploy.const_defined?(definition["kind"])
        klass = KubernetesDeploy.const_get(definition["kind"])
        klass.new(**opts)
      else
        inst = new(**opts)
        inst.type = definition["kind"]
        inst
      end
    end

    def self.timeout
      self::TIMEOUT
    end

    def timeout
      return timeout_override if timeout_override.present?
      self.class.timeout
    end

    def timeout_override
      return @timeout_override if defined?(@timeout_override)
      @timeout_override = DurationParser.new(timeout_annotation).parse!.to_i
    rescue DurationParser::ParsingError
      @timeout_override = nil
    end

    def pretty_timeout_type
      "timeout: #{timeout}s"
    end

    def initialize(namespace:, context:, definition:, logger:)
      # subclasses must also set these if they define their own initializer
      @name = definition.dig("metadata", "name")
      unless @name.present?
        logger.summary.add_paragraph("Rendered template content:\n#{definition.to_yaml}")
        raise FatalDeploymentError, "Template is missing required field metadata.name"
      end

      @namespace = namespace
      @context = context
      @logger = logger
      @definition = definition
      @statsd_report_done = false
      @validation_errors = []
    end

    def validate_definition(selector = nil)
      @validation_errors = []
      validate_selector(selector) if selector
      validate_timeout_annotation

      command = ["create", "-f", file_path, "--dry-run", "--output=name"]
      _, err, st = kubectl.run(*command, log_failure: false)
      return true if st.success?
      @validation_errors << err
      false
    end

    def validation_error_msg
      @validation_errors.join("\n")
    end

    def validation_failed?
      @validation_errors.present?
    end

    def id
      "#{type}/#{name}"
    end

    def file_path
      file.path
    end

    def sync
    end

    def deploy_failed?
      false
    end

    def deploy_started?
      @deploy_started_at.present?
    end

    def deploy_succeeded?
      if deploy_started? && !@success_assumption_warning_shown
        @logger.warn("Don't know how to monitor resources of type #{type}. Assuming #{id} deployed successfully.")
        @success_assumption_warning_shown = true
      end
      true
    end

    def exists?
      nil
    end

    def status
      @status ||= "Unknown"
    end

    def type
      @type || self.class.name.demodulize
    end

    def deploy_timed_out?
      return false unless deploy_started?
      !deploy_succeeded? && !deploy_failed? && (Time.now.utc - @deploy_started_at > timeout)
    end

    # Expected values: :apply, :replace, :replace_force
    def deploy_method
      :apply
    end

    def sync_debug_info
      @events = fetch_events unless ENV[DISABLE_FETCHING_EVENT_INFO]
      @logs = fetch_logs if supports_logs? && !ENV[DISABLE_FETCHING_EVENT_INFO]
      @debug_info_synced = true
    end

    def debug_message
      sync_debug_info unless @debug_info_synced

      helpful_info = []
      if deploy_failed?
        helpful_info << ColorizedString.new("#{id}: FAILED").red
        helpful_info << failure_message if failure_message.present?
      elsif deploy_timed_out?
        helpful_info << ColorizedString.new("#{id}: TIMED OUT (#{pretty_timeout_type})").yellow
        helpful_info << timeout_message if timeout_message.present?
      else
        # Arriving in debug_message when we neither failed nor timed out is very unexpected. Dump all available info.
        helpful_info << ColorizedString.new("#{id}: MONITORING ERROR").red
        helpful_info << failure_message if failure_message.present?
        helpful_info << timeout_message if timeout_message.present? && timeout_message != STANDARD_TIMEOUT_MESSAGE
      end
      helpful_info << "  - Final status: #{status}"

      if @events.present?
        helpful_info << "  - Events (common success events excluded):"
        @events.each do |identifier, event_hashes|
          event_hashes.each { |event| helpful_info << "      [#{identifier}]\t#{event}" }
        end
      elsif ENV[DISABLE_FETCHING_EVENT_INFO]
        helpful_info << "  - Events: #{DISABLED_EVENT_INFO_MESSAGE}"
      else
        helpful_info << "  - Events: #{DEBUG_RESOURCE_NOT_FOUND_MESSAGE}"
      end

      if supports_logs?
        if ENV[DISABLE_FETCHING_LOG_INFO]
          helpful_info << "  - Logs: #{DISABLED_LOG_INFO_MESSAGE}"
        elsif @logs.blank? || @logs.values.all?(&:blank?)
          helpful_info << "  - Logs: #{DEBUG_RESOURCE_NOT_FOUND_MESSAGE}"
        else
          sorted_logs = @logs.sort_by { |_, log_lines| log_lines.length }
          sorted_logs.each do |identifier, log_lines|
            if log_lines.empty?
              helpful_info << "  - Logs from container '#{identifier}': #{DEBUG_RESOURCE_NOT_FOUND_MESSAGE}"
              next
            end

            helpful_info << "  - Logs from container '#{identifier}' (last #{LOG_LINE_COUNT} lines shown):"
            log_lines.each do |line|
              helpful_info << "      #{line}"
            end
          end
        end
      end

      helpful_info.join("\n")
    end

    # Returns a hash in the following format:
    # {
    #   "pod/web-1" => [
    #     "Pulling: pulling image "hello-world:latest" (1 events)",
    #     "Pulled: Successfully pulled image "hello-world:latest" (1 events)"
    #   ]
    # }
    def fetch_events
      return {} unless exists?
      out, _err, st = kubectl.run("get", "events", "--output=go-template=#{Event.go_template_for(type, name)}")
      return {} unless st.success?

      event_collector = Hash.new { |hash, key| hash[key] = [] }
      Event.extract_all_from_go_template_blob(out).each_with_object(event_collector) do |candidate, events|
        events[id] << candidate.to_s if candidate.seen_since?(@deploy_started_at - 5.seconds)
      end
    end

    def timeout_message
      STANDARD_TIMEOUT_MESSAGE
    end

    def failure_message
    end

    def pretty_status
      padding = " " * [50 - id.length, 1].max
      msg = exists? ? status : "not found"
      "#{id}#{padding}#{msg}"
    end

    def kubectl
      @kubectl ||= Kubectl.new(namespace: @namespace, context: @context, logger: @logger, log_failure_by_default: false)
    end

    def report_status_to_statsd(watch_time)
      unless @statsd_report_done
        ::StatsD.measure('resource.duration', watch_time, tags: statsd_tags)
        @statsd_report_done = true
      end
    end

    class Event
      EVENT_SEPARATOR = "ENDEVENT--BEGINEVENT"
      FIELD_SEPARATOR = "ENDFIELD--BEGINFIELD"
      FIELDS = %w(
        .involvedObject.kind
        .involvedObject.name
        .count
        .lastTimestamp
        .reason
        .message
      )

      def self.go_template_for(kind, name)
        and_conditions = [
          %[(eq .involvedObject.kind "#{kind}")],
          %[(eq .involvedObject.name "#{name}")],
          '(ne .reason "Started")',
          '(ne .reason "Created")',
          '(ne .reason "SuccessfulCreate")',
          '(ne .reason "Scheduled")',
          '(ne .reason "Pulling")',
          '(ne .reason "Pulled")'
        ]
        condition_start = "{{if and #{and_conditions.join(' ')}}}"
        field_part = FIELDS.map { |f| "{{#{f}}}" }.join(%({{print "#{FIELD_SEPARATOR}"}}))
        %({{range .items}}#{condition_start}#{field_part}{{print "#{EVENT_SEPARATOR}"}}{{end}}{{end}})
      end

      def self.extract_all_from_go_template_blob(blob)
        blob.split(EVENT_SEPARATOR).map do |event_blob|
          pieces = event_blob.split(FIELD_SEPARATOR, FIELDS.length)
          new(
            subject_kind: pieces[FIELDS.index(".involvedObject.kind")],
            subject_name: pieces[FIELDS.index(".involvedObject.name")],
            count: pieces[FIELDS.index(".count")],
            last_timestamp: pieces[FIELDS.index(".lastTimestamp")],
            reason: pieces[FIELDS.index(".reason")],
            message: pieces[FIELDS.index(".message")]
          )
        end
      end

      def initialize(subject_kind:, last_timestamp:, reason:, message:, count:, subject_name:)
        @subject_kind = subject_kind
        @subject_name = subject_name
        @last_timestamp = Time.parse(last_timestamp)
        @reason = reason
        @message = message.tr("\n", '')
        @count = count.to_i
      end

      def seen_since?(time)
        time.to_i <= @last_timestamp.to_i
      end

      def to_s
        "#{@reason}: #{@message} (#{@count} events)"
      end
    end

    private

    def validate_timeout_annotation
      return if timeout_annotation.nil?

      override = DurationParser.new(timeout_annotation).parse!
      if override <= 0
        @validation_errors << "#{TIMEOUT_OVERRIDE_ANNOTATION} annotation is invalid: Value must be greater than 0"
      elsif override > 24.hours
        @validation_errors << "#{TIMEOUT_OVERRIDE_ANNOTATION} annotation is invalid: Value must be less than 24h"
      end
    rescue DurationParser::ParsingError => e
      @validation_errors << "#{TIMEOUT_OVERRIDE_ANNOTATION} annotation is invalid: #{e}"
    end

    def timeout_annotation
      @definition.dig("metadata", "annotations", TIMEOUT_OVERRIDE_ANNOTATION)
    end

    def validate_selector(selector)
      selector_string = Utils.selector_to_string(selector)

      if labels.nil?
        @validation_errors << "selector #{selector_string} passed in, but no labels were defined"
        return
      end

      unless selector <= labels
        label_name = 'label'.pluralize(labels.size)
        label_string = Utils.selector_to_string(labels)
        @validation_errors << "selector #{selector_string} does not match #{label_name} #{label_string}"
      end
    end

    def labels
      @definition.dig("metadata", "labels")
    end

    def file
      @file ||= create_definition_tempfile
    end

    def create_definition_tempfile
      file = Tempfile.new(["#{type}-#{name}", ".yml"])
      file.write(YAML.dump(@definition))
      file
    ensure
      file&.close
    end

    def supports_logs?
      respond_to?(:fetch_logs)
    end

    def statsd_tags
      status = if deploy_failed?
        "failure"
      elsif deploy_timed_out?
        "timeout"
      elsif deploy_succeeded?
        "success"
      else
        "unknown"
      end
      %W(context:#{context} namespace:#{namespace} resource:#{id} type:#{type} sha:#{ENV['REVISION']} status:#{status})
    end
  end
end
