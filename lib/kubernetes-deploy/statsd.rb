# frozen_string_literal: true
require 'statsd-instrument'
require 'logger'

module KubernetesDeploy
  class StatsD
    def self.duration(start_time)
      (Time.now.utc - start_time).round(1)
    end

    def self.build
      ::StatsD.default_sample_rate = 1.0
      ::StatsD.prefix = "KubernetesDeploy"

      if ENV['STATSD_DEV'].present?
        ::StatsD.backend = ::StatsD::Instrument::Backends::LoggerBackend.new(Logger.new($stderr))
      elsif ENV['STATSD_ADDR'].present?
        statsd_impl = ENV['STATSD_IMPLEMENTATION'].empty? ? "datadog" : ENV['STATSD_IMPLEMENTATION']
        ::StatsD.backend = ::StatsD::Instrument::Backends::UDPBackend.new(ENV['STATSD_ADDR'], statsd_impl)
      else
        ::StatsD.backend = ::StatsD::Instrument::Backends::NullBackend.new
      end
      ::StatsD.backend
    end
  end
end
