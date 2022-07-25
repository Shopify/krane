# frozen_string_literal: true

module Krane
  class APIResource
    attr_reader :group, :kind, :namespaced

    def initialize(group, kind, namespaced)
      @group = group
      @kind = kind
      @namespaced = namespaced
    end

    def group_kind
      ::Krane::KubernetesResource.combine_group_kind(@group, @kind)
    end
  end
end
