# frozen_string_literal: true
require 'test_helper'

class ResourceDiscoveryTest < KubernetesDeploy::IntegrationTest
  def cleanup
    crd_list = apiextensions_v1beta1_kubeclient.get_custom_resource_definitions
    crd_list.each do |res|
      apiextensions_v1beta1_kubeclient.delete_custom_resource_definition res.metadata.name
    end
  end

  def test_invalid_crd_query
    skip if KUBE_SERVER_VERSION < Gem::Version.new('1.7.0')
    begin
      assert_deploy_success(deploy_fixtures("resource-discovery/definitions", subset: ["crd_invalid_query.yml"]))
      # Deploy any other resource to trigger discovery
      assert_deploy_failure(deploy_fixtures("resource-discovery/instances", subset: ["crd.yml"]))
      assert_logs_match_all([
        "Invalid status query for for api.foobar.com/v1/widget: '('",
      ], in_order: true)
    ensure
      cleanup
    end
  end

  def test_invalid_crd_metadata
    skip if KUBE_SERVER_VERSION < Gem::Version.new('1.7.0')
    begin
      assert_deploy_success(deploy_fixtures("resource-discovery/definitions", subset: ["crd_invalid_metadata.yml"]))
      # Deploy any other resource to trigger discovery
      assert_deploy_failure(deploy_fixtures("hello-cloud", subset: ["configmap-data.yml",]))
      assert_logs_match_all([
        "Invalid metadata for api.foobar.com/v1/widget",
        "unexpected token at '{ \"status-success\": }'"
      ], in_order: true)
    ensure
      cleanup
    end
  end

  def test_non_prunable_crd_no_predeploy
    skip if KUBE_SERVER_VERSION < Gem::Version.new('1.7.0')
    begin
      assert_deploy_success(deploy_fixtures("resource-discovery/definitions",
        subset: ["crd_non_prunable_no_predeploy.yml"]))
      assert_deploy_success(deploy_fixtures("resource-discovery/instances", subset: ["crd.yml"]))
      # Deploy any other non-priority (predeployable) resource to trigger pruning
      assert_deploy_success(deploy_fixtures("hello-cloud", subset: ["daemon_set.yml",]))

      refute_logs_match("The following resources were pruned: widget \"my-first-widget\"")
      refute_logs_match("Don't know how to monitor resources of type Widget. " \
                        "Assuming Widget/my-first-widget deployed successfully")
      # Should predeploy the CR definition, but *not* the instance.
      assert_logs_match(%r{
        Predeploying\spriority\sresources
        \-+\s+\[INFO\]                     # Line header
        \[(\d|\-|\s|\:|\+)+\]\s+           # Timestamp
        Deploying\sCustomResourceDefinition
        \/widgets\.api\.foobar\.com
      }x)
      refute_logs_match(%r{
        Predeploying\spriority\sresources
        \-+\s+\[INFO\]                     # Line header
        \[(\d|\-|\s|\:|\+)+\]\s+           # Timestamp
        Deploying\sWidget
        \/my\-first\-widget
      }x)
    ensure
      cleanup
    end
  end

  def test_prunable_crd_with_predeploy
    skip if KUBE_SERVER_VERSION < Gem::Version.new('1.7.0')
    begin
      assert_deploy_success(deploy_fixtures("resource-discovery/definitions", subset: ["crd.yml"]))
      assert_deploy_success(deploy_fixtures("resource-discovery/instances", subset: ["crd.yml"]))
      # Deploy any other resource to trigger pruning
      assert_deploy_success(deploy_fixtures("hello-cloud", subset: ["configmap-data.yml",]))
      # Should predeploy the CR definition, *and* the instance.
      assert_logs_match(%r{
        Predeploying\spriority\sresources
        \-+\s+\[INFO\]                     # Line header
        \[(\d|\-|\s|\:|\+)+\]\s+           # Timestamp
        Deploying\sCustomResourceDefinition
        \/widgets\.api\.foobar\.com
      }x)
      assert_logs_match(%r{
        Predeploying\spriority\sresources
        \-+\s+\[INFO\]                     # Line header
        \[(\d|\-|\s|\:|\+)+\]\s+           # Timestamp
        Deploying\sWidget
        \/my\-first\-widget
      }x)
      assert_logs_match("The following resources were pruned: widget \"my-first-widget\"")
      refute_logs_match("Don't know how to monitor resources of type Widget. " \
                        "Assuming Widget/my-first-widget deployed successfully")
    ensure
      cleanup
    end
  end
end
