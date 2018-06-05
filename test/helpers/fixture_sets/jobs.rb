# frozen_string_literal: true
module FixtureSetAssertions
  class Jobs < FixtureSet
    def initialize(namespace)
      @namespace = namespace
      @app_name = "jobs"
    end

    def assert_job_present(job_name)
      assert_job_exists(job_name)
    end
  end
end
