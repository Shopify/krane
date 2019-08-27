# frozen_string_literal: true
require 'test_helper'
require 'krane/cli/krane'

class KraneTest < KubernetesDeploy::TestCase
  def test_version_prints_current_version
    assert_output(nil, /Krane Version: #{KubernetesDeploy::VERSION}/) { krane.version }
  end

  private

  def krane
    Krane::CLI::Krane.new
  end
end
