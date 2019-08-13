# frozen_string_literal: true
require 'test_helper'

class KraneTest < KubernetesDeploy::TestCase
  def test_version_prints_current_version
    assert(krane.version)
    assert_logs_match_all([
      "Krane Version: #{KubernetesDeploy::VERSION}",
    ], in_order: true)
  end

  private

  def krane
    @krane = Krane.new.tap do |krane|
      krane.instance_variable_set('@logger', @logger)
    end
  end
end
