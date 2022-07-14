# frozen_string_literal: true
module Krane
  class PriorityClass < KubernetesResource
    GROUPS = ["scheduling.k8s.io"]
  end
end
