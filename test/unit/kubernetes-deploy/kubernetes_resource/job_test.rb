# frozen_string_literal: true
require 'test_helper'

class JobTest < KubernetesDeploy::TestCase
  include ResourceCacheTestHelper

  def test_job_fails_with_failed_status_condition
    status = {
      status: {
        conditions: [{
          lastProbeTime: "2018-10-12T19:49:33Z",
          lastTransitionTime: "2018-10-12T19:49:33",
          message: "Job has reached the specified backoff limit",
          reason: "BackoffLimitExceeded",
          status: "True",
          type: "Failed",
        }],
        failed: 2,
        startTime: "2018-10-12T19:49:28Z",
      },
    }
    job = build_synced_job(job_spec.merge(status).deep_stringify_keys)

    assert_predicate(job, :deploy_failed?)

    expected_msg = "BackoffLimitExceeded (Job has reached the specified backoff limit)"
    assert_equal(expected_msg, job.failure_message)
  end

  def test_job_fails_without_failed_status_condition
    definition = {
      spec: {
        backoffLimit: 1,
      },
      status: {
        failed: 2,
        startTime: "2018-10-12T19:49:28Z",
      },
    }
    job = build_synced_job(job_spec.merge(definition).deep_stringify_keys)

    assert_predicate(job, :deploy_failed?)
  end

  private

  def job_spec
    { metadata: { name: 'test-job' } }
  end

  def build_synced_job(template)
    job = KubernetesDeploy::Job.new(namespace: 'test', context: 'nope', definition: template,
      logger: @logger)
    job.deploy_started_at = Time.now.utc
    stub_kind_get("Job", items: [template])
    job.sync(build_resource_cache)
    job
  end
end
