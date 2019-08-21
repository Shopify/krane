# frozen_string_literal: true

require 'kubernetes-deploy/version'

module Krane
  class Version
    def initialize
      @gem_version = Gem::Version.new(KubernetesDeploy::VERSION)
    end

    def to_s
      @gem_version.version
    end

    def patch
      @gem_version.segments[2]
    end

    def major
      @gem_version.segments[0]
    end

    def minor
      @gem_version.segments[1]
    end

    def to_h
      {
        "version" => @gem_version.version,
        "major" => major,
        "minor" => minor,
        "patch" => patch,
      }
    end
  end
end
