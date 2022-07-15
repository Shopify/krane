# frozen_string_literal: true
module Krane
  class StorageClass < KubernetesResource
    GROUPS = ["storage.k8s.io"]
  end
end
