# frozen_string_literal: true
module Krane
  module StorageK8sIo
    class StorageClass < KubernetesResource
      DEFAULT_CLASS_ANNOTATION = "storageclass.kubernetes.io/is-default-class"
      DEFAULT_CLASS_BETA_ANNOTATION = "storageclass.beta.kubernetes.io/is-default-class"

      attr_reader :name

      def initialize(definition)
        super(definition: definition, namespace: nil, context: nil, logger: nil)
        @definition = definition
        @name = definition.dig("metadata", "name").to_s
      end

      def volume_binding_mode
        @definition.dig("volumeBindingMode")
      end

      def default?
        @definition.dig("metadata", "annotations", DEFAULT_CLASS_ANNOTATION) == "true" ||
        @definition.dig("metadata", "annotations", DEFAULT_CLASS_BETA_ANNOTATION) == "true"
      end
    end
  end
end
