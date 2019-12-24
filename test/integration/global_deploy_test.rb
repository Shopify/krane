# frozen_string_literal: true
require 'integration_test_helper'

class GlobalDeployTest < Krane::IntegrationTest
  def test_global_deploy_task_success
    assert_deploy_success(deploy_global_fixtures('globals'))

    assert_logs_match_all([
      "Phase 1: Initializing deploy",
      "Using resource selector app=krane,test=",
      "All required parameters and files are present",
      "Discovering resources:",
      "  - StorageClass/#{storage_class_name}",
      "Phase 2: Checking initial resource statuses",
      %r{StorageClass\/#{storage_class_name}\s+Not Found},
      "Phase 3: Deploying all resources",
      "Deploying resources:",
      %r{StorageClass\/#{storage_class_name} \(timeout: 300s\)},
      %r{PriorityClass/#{priority_class_name} \(timeout: 300s\)},
      "Don't know how to monitor resources of type StorageClass.",
      %r{Assuming StorageClass\/#{storage_class_name} deployed successfully.},
      %r{Successfully deployed in [\d.]+s: PriorityClass/#{priority_class_name}, StorageClass\/#{storage_class_name}},
      "Result: SUCCESS",
      "Successfully deployed 2 resources",
      "Successful resources",
      "StorageClass/#{storage_class_name}",
      "PriorityClass/#{priority_class_name}",
    ])
  end

  def test_global_deploy_task_success_timeout
    assert_deploy_failure(deploy_global_fixtures('globals', global_timeout: 0), :timed_out)

    assert_logs_match_all([
      "Phase 1: Initializing deploy",
      "Using resource selector app=krane,test=",
      "All required parameters and files are present",
      "Discovering resources:",
      "  - StorageClass/#{storage_class_name}",
      "Phase 2: Checking initial resource statuses",
      %r{StorageClass\/#{storage_class_name}\s+Not Found},
      "Phase 3: Deploying all resources",
      "Deploying resources:",
      "Result: TIMED OUT",
      "Timed out waiting for 2 resources to deploy",
      %r{StorageClass\/#{storage_class_name}: GLOBAL WATCH TIMEOUT \(0 seconds\)},
      "If you expected it to take longer than 0 seconds for your deploy to roll out, increase --global-timeout.",
    ])
  end

  def test_global_deploy_task_success_verify_false
    assert_deploy_success(deploy_global_fixtures('globals', verify_result: false))

    assert_logs_match_all([
      "Phase 1: Initializing deploy",
      "Using resource selector app=krane,test=",
      "All required parameters and files are present",
      "Discovering resources:",
      "  - StorageClass/#{storage_class_name}",
      "  - PriorityClass/#{priority_class_name}",
      "Phase 2: Checking initial resource statuses",
      %r{StorageClass\/#{storage_class_name}\s+Not Found},
      %r{PriorityClass/#{priority_class_name}\s+Not Found},
      "Phase 3: Deploying all resources",
      "Deploying resources:",
      %r{StorageClass\/#{storage_class_name} \(timeout: 300s\)},
      %r{PriorityClass/#{priority_class_name} \(timeout: 300s\)},
      "Result: SUCCESS",
      "Deployed 2 resources",
      "Deploy result verification is disabled for this deploy.",
      "This means the desired changes were communicated to Kubernetes, but the"\
      " deploy did not make sure they actually succeeded.",
    ])
  end

  def test_global_deploy_task_empty_selector_validation_failure
    assert_deploy_failure(deploy_global_fixtures('globals', selector: false))
    assert_logs_match_all([
      "Phase 1: Initializing deploy",
      "Result: FAILURE",
      "Configuration invalid",
      "- Selector is required",
    ])
  end

  def test_global_deploy_task_success_selector
    selector = "extraSelector=krane2"
    assert_deploy_success(deploy_global_fixtures('globals', selector: selector))

    assert_logs_match_all([
      "Phase 1: Initializing deploy",
      "Using resource selector #{selector}", # there are more, but this one should be listed first
      "All required parameters and files are present",
      "Discovering resources:",
      "  - StorageClass/#{storage_class_name}",
      "Phase 2: Checking initial resource statuses",
      %r{StorageClass\/#{storage_class_name}\s+Not Found},
      "Phase 3: Deploying all resources",
      "Deploying resources:",
      %r{PriorityClass/#{priority_class_name} \(timeout: 300s\)},
      %r{StorageClass\/#{storage_class_name} \(timeout: 300s\)},
      "Don't know how to monitor resources of type StorageClass.",
      "Assuming StorageClass/#{storage_class_name} deployed successfully.",
      /Successfully deployed in [\d.]+s/,
      "Result: SUCCESS",
      "Successfully deployed 2 resources",
      "Successful resources",
      "StorageClass/#{storage_class_name}",
      "PriorityClass/#{priority_class_name}",
    ])
  end

  def test_global_deploy_task_failure
    result = deploy_global_fixtures('globals') do |fixtures|
      fixtures.dig("storage_classes.yml", "StorageClass").first["metadata"]['badField'] = "true"
    end
    assert_deploy_failure(result)

    assert_logs_match_all([
      "Phase 1: Initializing deploy",
      "Using resource selector app=krane,test=",
      "All required parameters and files are present",
      "Discovering resources:",
      "  - StorageClass/#{storage_class_name}",
      "Result: FAILURE",
      "Template validation failed",
    ])
  end

  def test_global_deploy_prune_success
    selector = 'extraSelector=prune1'
    assert_deploy_success(deploy_global_fixtures('globals', selector: selector))
    reset_logger
    assert_deploy_success(deploy_global_fixtures('globals', subset: 'storage_classes.yml', selector: selector))

    assert_logs_match_all([
      "Phase 1: Initializing deploy",
      "Using resource selector #{selector}",
      "All required parameters and files are present",
      "Discovering resources:",
      "  - StorageClass/#{storage_class_name}",
      "Phase 2: Checking initial resource statuses",
      %r{StorageClass\/#{storage_class_name}\s+Exists},
      "Phase 3: Deploying all resources",
      %r{Deploying StorageClass\/#{storage_class_name} \(timeout: 300s\)},
      "The following resources were pruned: priorityclass.scheduling.k8s.io/#{priority_class_name}",
      %r{Successfully deployed in [\d.]+s: StorageClass\/#{storage_class_name}},
      "Result: SUCCESS",
      "Pruned 1 resource and successfully deployed 1 resource",
      "Successful resources",
      "StorageClass/#{storage_class_name}",
    ])
  end

  def test_no_prune_global_deploy_success
    selector = 'extraSelector=prune2'
    assert_deploy_success(deploy_global_fixtures('globals', selector: selector))
    reset_logger
    assert_deploy_success(deploy_global_fixtures('globals', subset: 'storage_classes.yml',
      selector: selector, prune: false))
    assert_logs_match_all([
      "Phase 1: Initializing deploy",
      "Using resource selector #{selector}",
      "All required parameters and files are present",
      "Discovering resources:",
      "  - StorageClass/#{storage_class_name}",
      "Phase 2: Checking initial resource statuses",
      %r{StorageClass\/#{storage_class_name}\s+Exists},
      "Phase 3: Deploying all resources",
      %r{Deploying StorageClass\/#{storage_class_name} \(timeout: 300s\)},
      %r{Successfully deployed in [\d.]+s: StorageClass\/#{storage_class_name}},
      "Result: SUCCESS",
      "Successfully deployed 1 resource",
      "Successful resources",
      "StorageClass/#{storage_class_name}",
    ])
    refute_logs_match(/[pP]runed/)
    refute_logs_match(priority_class_name)
    assert_deploy_success(deploy_global_fixtures('globals', selector: selector))
  end

  private

  def storage_class_name
    @storage_class_name ||= add_unique_prefix_for_test("testing-storage-class")
  end

  def priority_class_name
    @priority_class_name ||= add_unique_prefix_for_test("testing-priority-class")
  end
end
