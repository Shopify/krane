# frozen_string_literal: true
require 'json'
require 'shellwords'

require 'krane/remote_logs'
require 'krane/duration_parser'
require 'krane/label_selector'
require 'krane/rollout_conditions'
require 'krane/psych_k8s_compatibility'

module Krane
  class KubernetesResource
    using PsychK8sCompatibility

    attr_reader :name, :namespace, :context
    attr_writer :type, :deploy_started_at, :global

    GLOBAL = false
    TIMEOUT = 5.minutes
    LOG_LINE_COUNT = 250
    SERVER_DRY_RUN_DISABLED_ERROR =
      /(unknown flag: --server-dry-run)|(does[\s\']n[o|']t support dry[-\s]run)|(dryRun alpha feature is disabled)/

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

    ALLOWED_DEPLOY_METHOD_OVERRIDES = %w(create replace replace-force)
    DEPLOY_METHOD_OVERRIDE_ANNOTATION = "deploy-method-override"
    TIMEOUT_OVERRIDE_ANNOTATION = "timeout-override"
    LAST_APPLIED_ANNOTATION = "kubectl.kubernetes.io/last-applied-configuration"
    SENSITIVE_TEMPLATE_CONTENT = false
    SERVER_DRY_RUNNABLE = false
    SYNC_DEPENDENCIES = []

    class << self
      def build(namespace: nil, context:, definition:, logger:, statsd_tags:, crd: nil, global_names: [])
        validate_definition_essentials(definition)
        opts = { namespace: namespace, context: context, definition: definition, logger: logger,
                 statsd_tags: statsd_tags }
        if (klass = class_for_kind(definition["kind"]))
          return klass.new(**opts)
        end
        if crd
          CustomResource.new(crd: crd, **opts)
        else
          type = definition["kind"]
          inst = new(**opts)
          inst.type = type
          inst.global = global_names.map(&:downcase).include?(type.downcase)
          inst
        end
      end

      def class_for_kind(kind)
        if Krane.const_defined?(kind, false)
          Krane.const_get(kind, false)
        end
      rescue NameError
        nil
      end

      def timeout
        self::TIMEOUT
      end

      def kind
        name.demodulize
      end

      private

      def validate_definition_essentials(definition)
        debug_content = <<~STRING
          apiVersion: #{definition.fetch('apiVersion', '<missing>')}
          kind: #{definition.fetch('kind', '<missing>')}
          metadata: #{definition.fetch('metadata', {})}
          <Template body suppressed because content sensitivity could not be determined.>
        STRING
        if definition["kind"].blank?
          raise InvalidTemplateError.new("Template is missing required field 'kind'", content: debug_content)
        end

        if definition.dig('metadata', 'name').blank? && definition.dig('metadata', 'generateName').blank?
          raise InvalidTemplateError.new("Template must specify one of 'metadata.name' or 'metadata.generateName'",
            content: debug_content)
        end
      end
    end

    def timeout
      return timeout_override if timeout_override.present?
      self.class.timeout
    end

    def timeout_override
      return @timeout_override if defined?(@timeout_override)

      @timeout_override = DurationParser.new(krane_annotation_value(TIMEOUT_OVERRIDE_ANNOTATION)).parse!.to_i
    rescue DurationParser::ParsingError
      @timeout_override = nil
    end

    def pretty_timeout_type
      "timeout: #{timeout}s"
    end

    def initialize(namespace:, context:, definition:, logger:, statsd_tags: [])
      # subclasses must also set these if they define their own initializer
      @name = (definition.dig("metadata", "name") || definition.dig("metadata", "generateName")).to_s
      @optional_statsd_tags = statsd_tags
      @namespace = namespace
      @context = context
      @logger = logger
      @definition = definition
      @statsd_report_done = false
      @disappeared = false
      @validation_errors = []
      @instance_data = {}
      @server_dry_run_validated = false
    end

    def to_kubeclient_resource
      Kubeclient::Resource.new(@definition)
    end

    def validate_definition(kubectl:, selector: nil)
      @validation_errors = []
      validate_selector(selector) if selector
      validate_timeout_annotation
      validate_deploy_method_override_annotation
      # We may have validated by batch applying, so we don't always need kubectl here
      validate_spec_with_kubectl(kubectl) if kubectl
      @validation_errors.present?
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

    def <=>(other)
      id <=> other.id
    end

    def file_path
      file.path
    end

    def sync(cache)
      @instance_data = cache.get_instance(kubectl_resource_type, name, raise_if_not_found: true)
    rescue Krane::Kubectl::ResourceNotFoundError
      @disappeared = true if deploy_started?
      @instance_data = {}
    end

    def after_sync
    end

    def terminating?
      @instance_data.dig('metadata', 'deletionTimestamp').present?
    end

    def disappeared?
      @disappeared
    end

    def deploy_failed?
      false
    end

    def deploy_started?
      @deploy_started_at.present?
    end

    def deploy_succeeded?
      return false unless deploy_started?
      unless @success_assumption_warning_shown
        @logger.warn("Don't know how to monitor resources of type #{type}. Assuming #{id} deployed successfully.")
        @success_assumption_warning_shown = true
      end
      true
    end

    def exists?
      @instance_data.present?
    end

    def current_generation
      return -1 unless exists? # must be different default than observed_generation
      @instance_data.dig("metadata", "generation")
    end

    def observed_generation
      return -2 unless exists?
      # populating this is a best practice, but not all controllers actually do it
      @instance_data.dig('status', 'observedGeneration')
    end

    def status
      exists? ? "Exists" : "Not Found"
    end

    def type
      @type || self.class.kind
    end

    def group
      grouping, version = @definition.dig("apiVersion").split("/")
      version ? grouping : "core"
    end

    def kubectl_resource_type
      type
    end

    def deploy_timed_out?
      return false unless deploy_started?
      !deploy_succeeded? && !deploy_failed? && (Time.now.utc - @deploy_started_at > timeout)
    end

    # Expected values: :apply, :create, :replace, :replace_force
    def deploy_method
      if @definition.dig("metadata", "name").blank? && uses_generate_name?
        :create
      else
        deploy_method_override || :apply
      end
    end

    def deploy_method_override
      krane_annotation_value(DEPLOY_METHOD_OVERRIDE_ANNOTATION)&.to_sym
    end

    def sync_debug_info(kubectl)
      @debug_events = fetch_events(kubectl) unless ENV[DISABLE_FETCHING_EVENT_INFO]
      @debug_logs = fetch_debug_logs if print_debug_logs? && !ENV[DISABLE_FETCHING_LOG_INFO]
    end

    def debug_message(cause = nil, info_hash = {})
      helpful_info = []
      if cause == :gave_up
        debug_heading = ColorizedString.new("#{id}: GLOBAL WATCH TIMEOUT (#{info_hash[:timeout]} seconds)").yellow
        helpful_info << "If you expected it to take longer than #{info_hash[:timeout]} seconds for your deploy"\
        " to roll out, increase --global-timeout."
      elsif deploy_failed?
        debug_heading = ColorizedString.new("#{id}: FAILED").red
        helpful_info << failure_message if failure_message.present?
      elsif deploy_timed_out?
        debug_heading = ColorizedString.new("#{id}: TIMED OUT (#{pretty_timeout_type})").yellow
        helpful_info << timeout_message if timeout_message.present?
      else
        # Arriving in debug_message when we neither failed nor timed out is very unexpected. Dump all available info.
        debug_heading = ColorizedString.new("#{id}: MONITORING ERROR").red
        helpful_info << failure_message if failure_message.present?
        helpful_info << timeout_message if timeout_message.present? && timeout_message != STANDARD_TIMEOUT_MESSAGE
      end

      final_status = "  - Final status: #{status}"
      final_status = "\n#{final_status}" if helpful_info.present? && !helpful_info.last.end_with?("\n")
      helpful_info.prepend(debug_heading)
      helpful_info << final_status

      if @debug_events.present?
        helpful_info << "  - Events (common success events excluded):"
        @debug_events.each do |identifier, event_hashes|
          event_hashes.each { |event| helpful_info << "      [#{identifier}]\t#{event}" }
        end
      elsif ENV[DISABLE_FETCHING_EVENT_INFO]
        helpful_info << "  - Events: #{DISABLED_EVENT_INFO_MESSAGE}"
      else
        helpful_info << "  - Events: #{DEBUG_RESOURCE_NOT_FOUND_MESSAGE}"
      end

      if print_debug_logs?
        if ENV[DISABLE_FETCHING_LOG_INFO]
          helpful_info << "  - Logs: #{DISABLED_LOG_INFO_MESSAGE}"
        elsif @debug_logs.blank?
          helpful_info << "  - Logs: #{DEBUG_RESOURCE_NOT_FOUND_MESSAGE}"
        else
          container_logs = @debug_logs.container_logs.sort_by { |c| c.lines.length }
          container_logs.each do |logs|
            if logs.empty?
              helpful_info << "  - Logs from container '#{logs.container_name}': #{DEBUG_RESOURCE_NOT_FOUND_MESSAGE}"
              next
            end

            if logs.lines.length == ContainerLogs::DEFAULT_LINE_LIMIT
              truncated = " (last #{ContainerLogs::DEFAULT_LINE_LIMIT} lines shown)"
            end
            helpful_info << "  - Logs from container '#{logs.container_name}'#{truncated}:"
            logs.lines.each do |line|
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
    def fetch_events(kubectl)
      return {} unless exists?
      out, _err, st = kubectl.run("get", "events", "--output=go-template=#{Event.go_template_for(type, name)}",
        log_failure: false, use_namespace: !global?)
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
      "#{id}#{padding}#{status}"
    end

    def report_status_to_statsd(watch_time)
      unless @statsd_report_done
        StatsD.client.distribution('resource.duration', watch_time, tags: statsd_tags)
        @statsd_report_done = true
      end
    end

    def sensitive_template_content?
      self.class::SENSITIVE_TEMPLATE_CONTENT
    end

    def server_dry_runnable_resource?
      # generateName and server-side dry run are incompatible because the former only works with `create`
      # and the latter only works with `apply`
      self.class::SERVER_DRY_RUNNABLE && !uses_generate_name?
    end

    def uses_generate_name?
      @definition.dig('metadata', 'generateName').present?
    end

    def server_dry_run_validated?
      @server_dry_run_validated
    end

    # If a resource uses generateName, we don't know the full name of the resource until it's deployed to the cluster.
    # In this case, we need to update our local definition with the realized name in order to accurately track the
    # resource during deploy
    def use_generated_name(instance_data)
      @name = instance_data.dig('metadata', 'name')
      @definition['metadata']['name'] = @name
      @definition['metadata'].delete('generateName')
      @file = create_definition_tempfile
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
        .eventTime
        .deprecatedCount
        .deprecatedLastTimestamp
        .series
      )
      FIELD_EMPTY_VALUE = '<no value>'

      def self.go_template_for(kind, name)
        and_conditions = [
          %[(eq .involvedObject.kind "#{kind}")],
          %[(eq .involvedObject.name "#{name}")],
          '(ne .reason "Started")',
          '(ne .reason "Created")',
          '(ne .reason "SuccessfulCreate")',
          '(ne .reason "Scheduled")',
          '(ne .reason "Pulling")',
          '(ne .reason "Pulled")',
        ]
        condition_start = "{{if and #{and_conditions.join(' ')}}}"
        field_part = FIELDS.map { |f| "{{#{f}}}" }.join(%({{print "#{FIELD_SEPARATOR}"}}))
        %({{range .items}}#{condition_start}#{field_part}{{print "#{EVENT_SEPARATOR}"}}{{end}}{{end}})
      end

      def self.extract_all_from_go_template_blob(blob)
        blob.split(EVENT_SEPARATOR).map do |event_blob|
          pieces = event_blob.split(FIELD_SEPARATOR, FIELDS.length)
          count = extract_event_count(pieces)
          timestamp = extract_event_timestamp(pieces)

          new(
            subject_kind: pieces[FIELDS.index(".involvedObject.kind")],
            subject_name: pieces[FIELDS.index(".involvedObject.name")],
            count: count,
            last_timestamp: timestamp,
            reason: pieces[FIELDS.index(".reason")],
            message: pieces[FIELDS.index(".message")]
          )
        end
      end

      def self.extract_event_count(pieces)
        series = pieces[FIELDS.index(".series")]
        count = pieces[FIELDS.index(".count")]
        deprecated_count = pieces[FIELDS.index(".deprecatedCount")]

        # Find the right event count according to Kubernetes API and kubectl version
        if count.present? && count != FIELD_EMPTY_VALUE
          count # This is the default field, so let's try to use it first
        elsif series.present? && series != FIELD_EMPTY_VALUE
          # kubectl 1.16 uses Events/v1, which has the .series/.count field
          count_regex = /count:(?<value>\S+?(?=\s))/
          count_regex.match(series)['value']
        elsif deprecated_count.present? && deprecated_count != FIELD_EMPTY_VALUE
          # kubectl < 1.16 uses events.k8s.io/v1beta1, which has .deprecatedCount
          deprecated_count
        else
          "1" # Fallback to 1 when all count fields are null
        end
      end

      def self.extract_event_timestamp(pieces)
        series = pieces[FIELDS.index(".series")]
        last_timestamp = pieces[FIELDS.index(".lastTimestamp")]
        deprecated_timestamp = pieces[FIELDS.index(".deprecatedLastTimestamp")]

        # Find the right event timestamp according to Kubernetes API and kubectl version
        if last_timestamp.present? && last_timestamp != FIELD_EMPTY_VALUE
          last_timestamp # kubernetes 1.16 also exposes .last_timestamp field, so let's support it
        elsif series.present? && series != FIELD_EMPTY_VALUE
          # kubectl 1.16 uses Events/v1, which has the .series/.lastObservedTime field
          timestamp_regex = /lastObservedTime:(?<value>\S+?(?=\]))/
          timestamp_regex.match(series)['value']
        elsif deprecated_timestamp.present? && deprecated_timestamp != FIELD_EMPTY_VALUE
          # kubectl < 1.16 uses events.k8s.io/v1beta1, which has .deprecatedLastTimestamp
          deprecated_timestamp
        else
          pieces[FIELDS.index(".eventTime")] # Fallback to eventTime when other timestamp fields are null
        end
      end
      private_class_method :extract_event_timestamp, :extract_event_count

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

    def global?
      @global || self.class::GLOBAL
    end

    private

    def validate_timeout_annotation
      timeout_override_value = krane_annotation_value(TIMEOUT_OVERRIDE_ANNOTATION)
      timeout_annotation_key = Annotation.for(TIMEOUT_OVERRIDE_ANNOTATION)
      return if timeout_override_value.nil?

      override = DurationParser.new(timeout_override_value).parse!
      if override <= 0
        @validation_errors << "#{timeout_annotation_key} annotation is invalid: Value must be greater than 0"
      elsif override > 24.hours
        @validation_errors << "#{timeout_annotation_key} annotation is invalid: Value must be less than 24h"
      end
    rescue DurationParser::ParsingError => e
      @validation_errors << "#{timeout_annotation_key} annotation is invalid: #{e}"
    end

    def validate_deploy_method_override_annotation
      deploy_method_override_value = krane_annotation_value(DEPLOY_METHOD_OVERRIDE_ANNOTATION)
      deploy_method_override_annotation_key = Annotation.for(DEPLOY_METHOD_OVERRIDE_ANNOTATION)
      return unless deploy_method_override_value
      unless ALLOWED_DEPLOY_METHOD_OVERRIDES.include?(deploy_method_override_value)
        @validation_errors << "#{deploy_method_override_annotation_key} is invalid: Accepted values are: " \
          "#{ALLOWED_DEPLOY_METHOD_OVERRIDES.join(', ')} but got #{deploy_method_override_value}"
      end
    end

    def krane_annotation_value(suffix)
      @definition.dig("metadata", "annotations", Annotation.for(suffix))
    end

    def validate_selector(selector)
      if labels.nil?
        @validation_errors << "selector #{selector} passed in, but no labels were defined"
        return
      end

      unless selector.to_h <= labels
        label_name = 'label'.pluralize(labels.size)
        label_string = LabelSelector.new(labels).to_s
        @validation_errors << "selector #{selector} does not match #{label_name} #{label_string}"
      end
    end

    def validate_spec_with_kubectl(kubectl)
      err = ""
      if kubectl.server_dry_run_enabled? && server_dry_runnable_resource?
        _, err, st = validate_with_server_side_dry_run(kubectl)
        @server_dry_run_validated = st.success?
        return true if st.success?
      end

      if err.empty? || err.match(SERVER_DRY_RUN_DISABLED_ERROR)
        _, err, st = validate_with_local_dry_run(kubectl)
      end

      return true if st.success?
      @validation_errors << if sensitive_template_content?
        "Validation for #{id} failed. Detailed information is unavailable as the raw error may contain sensitive data."
      else
        err
      end
    end

    # Server side dry run is only supported on apply
    def validate_with_server_side_dry_run(kubectl)
      command = if kubectl.server_version >= Gem::Version.new('1.18')
        ["apply", "-f", file_path, "--dry-run=server", "--output=name"]
      else
        ["apply", "-f", file_path, "--server-dry-run", "--output=name"]
      end

      kubectl.run(*command, log_failure: false, output_is_sensitive: sensitive_template_content?,
        retry_whitelist: [:client_timeout, :empty, :context_deadline], attempts: 3)
    end

    # Local dry run is supported on only create and apply
    # If the deploy method is create, validating with apply will fail
    # If the resource template uses generateName, validating with apply will fail
    def validate_with_local_dry_run(kubectl)
      verb = deploy_method == :apply ? "apply" : "create"
      command = [verb, "-f", file_path, "--dry-run", "--output=name"]
      kubectl.run(*command, log_failure: false, output_is_sensitive: sensitive_template_content?,
        retry_whitelist: [:client_timeout, :empty, :context_deadline], attempts: 3, use_namespace: !global?)
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

    def print_debug_logs?
      false
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
      tags = %W(context:#{context} namespace:#{namespace} type:#{type} status:#{status})
      tags | @optional_statsd_tags
    end
  end
end
