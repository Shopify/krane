# frozen_string_literal: true
require 'test_helper'

class KubernetesResourceTest < Krane::TestCase
  def test_extra_labels
    [
      {kind: "ConfigMap"},
      {kind: "CronJob"},
      {kind: "CustomResourceDefinition"},
      {kind: "DaemonSet"},
      {kind: "Deployment"},
      {kind: "HorizontalPodAutoscaler"},
      {kind: "Ingress"},
      {kind: "Job"},
      {kind: "NetworkPolicy"},
      {kind: "PersistentVolumeClaim"},
      {kind: "PodDisruptionBudget"},
      {kind: "PodSetBase"},
      {kind: "PodTemplate"},
      {kind: "ReplicaSet"},
      {kind: "ResourceQuota"},
      {kind: "Role"},
      {kind: "RoleBinding"},
      {kind: "Secret"},
      {kind: "Service"},
      {kind: "ServiceAccount"},
      {kind: "StatefulSet"},

      {kind: "Pod", spec: {"containers" => [{"name" => "someContainer"}]}},
      {kind: "SomeCustomResource", init_args: {crd: "SomeCRD"}},
      {kind: "ResourceUnknownToKrane"},
    ].each do |resource|
      args = {
        namespace: 'test',
        context: 'nope',
        logger: @logger,
        statsd_tags: [],
        extra_labels: {
          "extra" => "label",
          "overwritten" => "yes"
        },
        definition: {
          "kind" => resource.fetch(:kind),
          "metadata" => {
            "name" => "testsuite",
            "labels" => {
              "overwritten" => "no"
            },
          },
          "spec" => resource.fetch(:spec, {})
        }
      }
      args.merge!(resource.fetch(:init_args, {}))

      resource = begin
        Krane::KubernetesResource.build(**args)
      rescue ArgumentError => e
        flunk("failed to build #{resource.fetch(:kind)}: #{e.message}")
      end

      assert_equal(resource.send(:labels),
        {"extra"=>"label", "overwritten"=>"no"},
        "expected #{resource} to apply extra_labels")
    end
  end
end
