# frozen_string_literal: true
require 'test_helper'

class ClusterResourceDiscoveryTest < Krane::TestCase
  def test_global_resource_kinds_failure
    crd = mocked_cluster_resource_discovery(nil, success: false)
    kinds = crd.global_resource_kinds
    assert_equal(kinds, [])
  end

  def test_global_resource_kinds_success
    crd = mocked_cluster_resource_discovery(api_resources_full_response)
    kinds = crd.global_resource_kinds
    assert_equal(kinds.length, api_resources_full_response.split("\n").length - 1)
    %w(MutatingWebhookConfiguration ComponentStatus CustomResourceDefinition).each do |kind|
      assert_includes(kinds, kind)
    end
  end

  def test_prunable_resources
    Krane::Kubectl.any_instance.stubs(:run).with("api-versions", attempts: 5, use_namespace: false)
      .returns([api_versions_full_response, "", stub(success?: true)])
    crd = mocked_cluster_resource_discovery(api_resources_full_response)
    kinds = crd.prunable_resources(namespaced: false)

    assert_equal(kinds.length, 13)
    %w(scheduling.k8s.io/v1beta1/PriorityClass storage.k8s.io/v1beta1/StorageClass).each do |kind|
      assert_includes(kinds, kind)
    end
    %w(node namespace).each do |black_lised_kind|
      assert_empty kinds.select { |k| k.downcase.include?(black_lised_kind) }
    end
  end

  private

  def mocked_cluster_resource_discovery(response, success: true)
    Krane::Kubectl.any_instance.stubs(:run)
      .with("api-resources", "--namespaced=false", attempts: 5, use_namespace: false, output: "wide")
      .returns([response, "", stub(success?: success)])
    Krane::ClusterResourceDiscovery.new(task_config: task_config, namespace_tags: [])
  end

  def api_versions_full_response
    %(admissionregistration.k8s.io/v1
admissionregistration.k8s.io/v1beta1
apiextensions.k8s.io/v1
apiextensions.k8s.io/v1beta1
apiregistration.k8s.io/v1
apiregistration.k8s.io/v1beta1
apps/v1
authentication.k8s.io/v1
authentication.k8s.io/v1beta1
authorization.k8s.io/v1
authorization.k8s.io/v1beta1
autoscaling/v1
autoscaling/v2beta1
autoscaling/v2beta2
batch/v1
batch/v1beta1
certificates.k8s.io/v1beta1
coordination.k8s.io/v1
coordination.k8s.io/v1beta1
events.k8s.io/v1beta1
extensions/v1beta1
networking.k8s.io/v1
networking.k8s.io/v1beta1
node.k8s.io/v1beta1
policy/v1beta1
rbac.authorization.k8s.io/v1
rbac.authorization.k8s.io/v1beta1
scheduling.k8s.io/v1
scheduling.k8s.io/v1beta1
storage.k8s.io/v1
storage.k8s.io/v1beta1
v1)
  end

  # rubocop:disable Metrics/LineLength
  def api_resources_full_response
    %(NAME                              SHORTNAMES   APIGROUP                       NAMESPACED   KIND                             VERBS
componentstatuses                 cs                                          false        ComponentStatus                  [get list]
namespaces                        ns                                          false        Namespace                        [create delete get list patch update watch]
nodes                             no                                          false        Node                             [create delete deletecollection get list patch update watch]
persistentvolumes                 pv                                          false        PersistentVolume                 [create delete deletecollection get list patch update watch]
mutatingwebhookconfigurations                  admissionregistration.k8s.io   false        MutatingWebhookConfiguration     [create delete deletecollection get list patch update watch]
validatingwebhookconfigurations                admissionregistration.k8s.io   false        ValidatingWebhookConfiguration   [create delete deletecollection get list patch update watch]
customresourcedefinitions         crd,crds     apiextensions.k8s.io           false        CustomResourceDefinition         [create delete deletecollection get list patch update watch]
apiservices                                    apiregistration.k8s.io         false        APIService                       [create delete deletecollection get list patch update watch]
tokenreviews                                   authentication.k8s.io          false        TokenReview                      [create]
selfsubjectaccessreviews                       authorization.k8s.io           false        SelfSubjectAccessReview          [create]
selfsubjectrulesreviews                        authorization.k8s.io           false        SelfSubjectRulesReview           [create]
subjectaccessreviews                           authorization.k8s.io           false        SubjectAccessReview              [create]
certificatesigningrequests        csr          certificates.k8s.io            false        CertificateSigningRequest        [create delete deletecollection get list patch update watch]
podsecuritypolicies               psp          extensions                     false        PodSecurityPolicy                [create delete deletecollection get list patch update watch]
podsecuritypolicies               psp          policy                         false        PodSecurityPolicy                [create delete deletecollection get list patch update watch]
clusterrolebindings                            rbac.authorization.k8s.io      false        ClusterRoleBinding               [create delete deletecollection get list patch update watch]
clusterroles                                   rbac.authorization.k8s.io      false        ClusterRole                      [create delete deletecollection get list patch update watch]
priorityclasses                   pc           scheduling.k8s.io              false        PriorityClass                    [create delete deletecollection get list patch update watch]
storageclasses                    sc           storage.k8s.io                 false        StorageClass                     [create delete deletecollection get list patch update watch]
volumeattachments                              storage.k8s.io                 false        VolumeAttachment                 [create delete deletecollection get list patch update watch])
  end
  # rubocop:enable Metrics/LineLength:
end
