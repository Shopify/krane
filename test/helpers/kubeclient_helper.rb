# frozen_string_literal: true
require 'kubernetes-deploy/kubeclient_builder'

module KubeclientHelper
  MINIKUBE_CONTEXT = "minikube"

  include KubernetesDeploy::KubeclientBuilder

  def kubeclient
    @kubeclient ||= build_v1_kubeclient(MINIKUBE_CONTEXT)
  end

  def v1beta1_kubeclient
    @v1beta1_kubeclient ||= build_v1beta1_kubeclient(MINIKUBE_CONTEXT)
  end

  def policy_v1beta1_kubeclient
    @policy_v1beta1_kubeclient ||= build_policy_v1beta1_kubeclient(MINIKUBE_CONTEXT)
  end

  def apps_v1beta1_kubeclient
    @apps_v1beta1_kubeclient ||= build_apps_v1beta1_kubeclient(MINIKUBE_CONTEXT)
  end

  def batch_v1beta1_kubeclient
    @batch_v1beta1_kubeclient ||= build_batch_v1beta1_kubeclient(MINIKUBE_CONTEXT)
  end
end
