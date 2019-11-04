# frozen_string_literal: true
require 'test_helper'

class ClusterResourceDiscoveryTest < Krane::TestCase
  def test_global_resource_kinds_failure
    crd = mocked_cluster_resource_discovery(nil, success: false)
    kinds = crd.global_resource_kinds
    assert_equal(kinds, [])
  end

  def test_global_resource_kinds_success
    crd = mocked_cluster_resource_discovery(full_response)
    kinds = crd.global_resource_kinds
    assert_equal(kinds.length, full_response.split("\n").length - 1)
    %w(MutatingWebhookConfiguration ComponentStatus CustomResourceDefinition).each do |kind|
      assert_includes(kinds, kind)
    end
  end

  def test_prunable_resources
    crd = mocked_cluster_resource_discovery(full_response)
    kinds = crd.prunable_resources
    assert_equal(kinds.length, 15)
    %w(scheduling.k8s.io/v1/PriorityClass storage.k8s.io/v1/StorageClass).each do |kind|
      assert_includes(kinds, kind)
    end
  end

  private

  def mocked_cluster_resource_discovery(response, success: true)
    Krane::Kubectl.any_instance.stubs(:run).returns([response, "", stub(success?: success)])
    Krane::ClusterResourceDiscovery.new(task_config: task_config, namespace_tags: [])
  end

  # rubocop:disable Metrics/LineLength
  def full_response
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
