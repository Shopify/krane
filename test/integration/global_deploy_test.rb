# frozen_string_literal: true
require 'integration_test_helper'

class SerialDeployTest < Krane::IntegrationTest
  include StatsDHelper
  def test_global_deploy_task_success
    assert_deploy_success(deploy_global_fixtures('globals'))

    assert_logs_match_all([
      "Phase 1: Initializing deploy",
      "Using resource selector test=",
      "All required parameters and files are present",
      "Discovering resources:",
      "  - StorageClass/testing-storage-class",
      "Phase 2: Checking initial resource statuses",
      %r{StorageClass\/testing-storage-class[\w-]+\s+Not Found},
      "Phase 3: Deploying all resources",
      %r{Deploying StorageClass\/testing-storage-class[\w-]+ \(timeout: 300s\)},
      "Don't know how to monitor resources of type StorageClass.",
      %r{Assuming StorageClass\/testing-storage-class[\w-]+ deployed successfully.},
      %r{Successfully deployed in 0.[\d]+s: StorageClass\/testing-storage-class},
      "Result: SUCCESS",
      "Successfully deployed 1 resource",
      "Successful resources",
      "StorageClass/testing-storage-class",
    ])
  end
end
