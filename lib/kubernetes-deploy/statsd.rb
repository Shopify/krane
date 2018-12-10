# frozen_string_literal: true
require 'statsd-instrument'
require 'logger'

module KubernetesDeploy
  class StatsD
    extend ::StatsD

    PREFIX = "KubernetesDeploy"

    def self.duration(start_time)
      (Time.now.utc - start_time).round(1)
    end

    def self.build
      if ENV['STATSD_DEV'].present?
        self.backend = ::StatsD::Instrument::Backends::LoggerBackend.new(Logger.new($stderr))
      elsif ENV['STATSD_ADDR'].present?
        statsd_impl = ENV['STATSD_IMPLEMENTATION'].present? ? ENV['STATSD_IMPLEMENTATION'] : "datadog"
        self.backend = ::StatsD::Instrument::Backends::UDPBackend.new(ENV['STATSD_ADDR'], statsd_impl)
      else
        self.backend = ::StatsD::Instrument::Backends::NullBackend.new
      end
    end

    # It is not sufficient to set the prefix field on the KubernetesDeploy::StatsD singleton itself, since its value
    # is overridden in the underlying calls to the ::StatsD library, hence the need to pass it in as a custom prefix
    # via the metric_options hash. This is done since KubernetesDeploy may be included as a library and should not
    # change the global StatsD configuration of the importing application.
    def self.increment(key, value = 1, **metric_options)
      metric_options[:prefix] = PREFIX
      super
    end

    def self.distribution(key, value = nil, **metric_options, &block)
      metric_options[:prefix] = PREFIX
      super
    end

    module MeasureMethods
      def measure_method(method_name, metric = nil)
        unless method_defined?(method_name) || private_method_defined?(method_name)
          raise NotImplementedError, "Cannot instrument undefined method #{method_name}"
        end

        unless const_defined?("InstrumentationProxy")
          const_set("InstrumentationProxy", Module.new)
          should_prepend = true
        end

        metric ||= "#{method_name}.duration"
        self::InstrumentationProxy.send(:define_method, method_name) do |*args, &block|
          begin
            start_time = Time.now.utc
            super(*args, &block)
          rescue
            error = true
            raise
          ensure
            dynamic_tags = send(:statsd_tags) if respond_to?(:statsd_tags, true)
            dynamic_tags ||= {}
            if error
              dynamic_tags[:error] = error if dynamic_tags.is_a?(Hash)
              dynamic_tags << "error:#{error}" if dynamic_tags.is_a?(Array)
            end

            StatsD.distribution(
              metric,
              KubernetesDeploy::StatsD.duration(start_time),
              tags: dynamic_tags
            )
          end
        end

        prepend(self::InstrumentationProxy) if should_prepend
      end
    end
  end
end
