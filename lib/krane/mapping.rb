module Krane
  MAPPING_GK = {
    "ConfigMap." => ::Krane::ConfigMap,
    "CronJob.batch" => ::Krane::CronJob,
    "DaemonSet.apps" => ::Krane::DaemonSet,
    "Deployment.apps" => ::Krane::Deployment,
    "MutatingWebhookConfiguration.admissionregistration.k8s.io" => ::Krane::MutatingWebhookConfiguration,
    "NetworkPolicy.networking.k8s.io" => ::Krane::NetworkPolicy,
  }
end
