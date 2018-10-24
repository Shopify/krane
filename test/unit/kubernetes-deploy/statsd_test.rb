# frozen_string_literal: true

require 'test_helper'

class StatsDTest < KubernetesDeploy::TestCase
  def test_build_when_statsd_addr_env_present_but_statsd_implementation_is_not
    original_addr = ENV['STATSD_ADDR']
    ENV['STATSD_ADDR'] = '127.0.0.1'
    original_impl = ENV['STATSD_IMPLEMENTATION']
    ENV['STATSD_IMPLEMENTATION'] = nil
    original_dev = ENV['STATSD_DEV']
    ENV['STATSD_DEV'] = nil

    KubernetesDeploy::StatsD.build

    assert_equal :datadog, StatsD.backend.implementation
  ensure
    ENV['STATSD_ADDR'] = original_addr
    ENV['STATSD_IMPLEMENTATION'] = original_impl
    ENV['STATSD_DEV'] = original_dev
    KubernetesDeploy::StatsD.build
  end
end
