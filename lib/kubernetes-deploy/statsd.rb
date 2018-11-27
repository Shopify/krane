# frozen_string_literal: true
require 'statsd-instrument'
require 'logger'

module KubernetesDeploy
  class StatsD
    extend ::StatsD
    def self.duration(start_time)
      (Time.now.utc - start_time).round(1)
    end

    def self.build
      self.default_sample_rate = 1.0
      self.prefix = "KubernetesDeploy"

      if ENV['STATSD_DEV'].present?
        self.backend = ::StatsD::Instrument::Backends::LoggerBackend.new(Logger.new($stderr))
      elsif ENV['STATSD_ADDR'].present?
        statsd_impl = ENV['STATSD_IMPLEMENTATION'].present? ? ENV['STATSD_IMPLEMENTATION'] : "datadog"
        self.backend = ::StatsD::Instrument::Backends::UDPBackend.new(ENV['STATSD_ADDR'], statsd_impl)
      else
        self.backend = ::StatsD::Instrument::Backends::NullBackend.new
      end
    end
  end
end
