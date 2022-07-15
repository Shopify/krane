module Krane
  MAPPING_GK = {
    "ConfigMap." => ::Krane.ConfigMap,
    "CronJob.batch" => ::Krane::CronJob,
    "DaemonSet.apps" => ::Krane::DaemonSet,
    "Deployment.apps" => ::Krane::Deployment,
    "HorizontalPodAutoscaler.autoscaling" => ::Krane::HorizontalPodAutoscaler,
    "Ingress.networking.k8s.io" => ::Krane::Ingress,
    "Job.batch" => ::Krane::Job,
    "MutatingWebhookConfiguration.admissionregistration.k8s.io" => ::Krane::MutatingWebhookConfiguration,
    "NetworkPolicy.networking.k8s.io" => ::Krane::NetworkPolicy,
    "PersistentVolumeClaim." => ::Krane::PersistentVolumeClaim,
    "PodDisruptionBudget.policy" => ::Krane::PodDisruptionBudget,
    "PodTemplate." => ::Krane::PodTemplate,
    "Pod." => ::Krane::Pod,
    "PriorityClass.scheduling.k8s.io" => ::Krane::PriorityClass,
    "ReplicaSet.apps" => ::Krane::ReplicaSet,
    "ResourceQuota." => ::Krane::ResourceQuota,
    "RoleBinding.rbac.authorization.k8s.io" => ::Krane::RoleBinding,
    "Role.rbac.authorization.k8s.io" => ::Krane::Role,
    "Secret." => ::Krane::Secret,
    "ServiceAccount." => ::Krane::ServiceAccount,
    "StatefulSet.apps" => ::Krane::StatefulSet,
    "StorageClass.storage.k8s.io" => ::Krane.StorageClass,
  }
end
