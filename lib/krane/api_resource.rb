# frozen_string_literal: true

module Krane
  class APIResource
    attr_reader :group, :kind, :version, :namespaced, :verbs

    def initialize(group, kind, version, namespaced, verbs)
      @group = group
      @kind = kind
      @version = version
      @namespaced = namespaced
      @verbs = verbs
    end

    def group_kind
      ::Krane::KubernetesResource.combine_group_kind(@group, @kind)
    end
  end
end
