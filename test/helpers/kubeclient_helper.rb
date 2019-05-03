# frozen_string_literal: true
require 'kubernetes-deploy/kubeclient_builder'

module KubeclientHelper
  LOCAL_CONTEXT_OVERRIDE_PATH = File.expand_path("../../.local-context", __dir__)
  if File.exist?(LOCAL_CONTEXT_OVERRIDE_PATH)
    TEST_CONTEXT = File.read(LOCAL_CONTEXT_OVERRIDE_PATH).split.first
  end
  TEST_CONTEXT ||= "minikube"

  def kubeclient
    @kubeclient ||= kubeclient_builder.build_v1_kubeclient(TEST_CONTEXT)
  end

  def v1beta1_kubeclient
    @v1beta1_kubeclient ||= kubeclient_builder.build_v1beta1_kubeclient(TEST_CONTEXT)
  end

  def policy_v1beta1_kubeclient
    @policy_v1beta1_kubeclient ||= kubeclient_builder.build_policy_v1beta1_kubeclient(TEST_CONTEXT)
  end

  def apps_v1beta1_kubeclient
    @apps_v1beta1_kubeclient ||= kubeclient_builder.build_apps_v1beta1_kubeclient(TEST_CONTEXT)
  end

  def batch_v1beta1_kubeclient
    @batch_v1beta1_kubeclient ||= kubeclient_builder.build_batch_v1beta1_kubeclient(TEST_CONTEXT)
  end

  def batch_v1_kubeclient
    @batch_v1_kubeclient ||= kubeclient_builder.build_batch_v1_kubeclient(TEST_CONTEXT)
  end

  def apiextensions_v1beta1_kubeclient
    @apiextensions_v1beta1_kubeclient ||= kubeclient_builder.build_apiextensions_v1beta1_kubeclient(TEST_CONTEXT)
  end

  def autoscaling_v1_kubeclient
    @autoscaling_v1_kubeclient ||= kubeclient_builder.build_autoscaling_v1_kubeclient(TEST_CONTEXT)
  end

  def rbac_v1_kubeclient
    @rbac_v1_kubeclient ||= kubeclient_builder.build_rbac_v1_kubeclient(TEST_CONTEXT)
  end

  def networking_v1_kubeclient
    @networking_v1_kubeclient ||= kubeclient_builder.build_networking_v1_kubeclient(TEST_CONTEXT)
  end

  def storage_v1_kubeclient
    @storage_v1_kubeclient ||= kubeclient_builder.build_storage_v1_kubeclient(TEST_CONTEXT)
  end

  def kubeclient_builder
    @kubeclient_builder ||= KubernetesDeploy::KubeclientBuilder.new
  end
end
