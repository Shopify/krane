# frozen_string_literal: true
module FixtureSetAssertions
  class CronJobs < FixtureSet
    def initialize(namespace)
      @namespace = namespace
      @app_name = "cronjobs"
    end

    def assert_cronjob_present(job_name)
      assert_cronjob_exists(job_name)
    end
  end
end
