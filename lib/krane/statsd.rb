# frozen_string_literal: true
require 'statsd-instrument'
require 'logger'

module Krane
  class StatsD
    PREFIX = "Krane"

    def self.duration(start_time)
      (Time.now.utc - start_time).round(1)
    end

    def self.client
      @client ||= begin
        sink = if ::StatsD::Instrument::Environment.current.env.fetch('STATSD_ENV', nil) == 'development'
          ::StatsD::Instrument::LogSink.new(Logger.new($stderr))
        elsif (addr = ::StatsD::Instrument::Environment.current.env.fetch('STATSD_ADDR', nil))
          ::StatsD::Instrument::UDPSink.for_addr(addr)
        else
          ::StatsD::Instrument::NullSink.new
        end
        ::StatsD::Instrument::Client.new(prefix: PREFIX, sink: sink, default_sample_rate: 1.0)
      end
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

            Krane::StatsD.client.distribution(
              metric,
              Krane::StatsD.duration(start_time),
              tags: dynamic_tags
            )
          end
        end

        prepend(self::InstrumentationProxy) if should_prepend
      end
    end
  end
end
