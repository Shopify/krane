# frozen_string_literal: true
module KubernetesDeploy
  class PersistentVolumeClaim < KubernetesResource
    TIMEOUT = 5.minutes

    def sync(cache)
      super
      @storage_classes = cache.get_all("StorageClass").map { |sc| StorageClass.new(sc) }
    end

    def status
      exists? ? @instance_data["status"]["phase"] : "Not Found"
    end

    def deploy_succeeded?
      return true if status == "Bound"

      # if the StorageClass has volumeBindingMode: WaitForFirstConsumer,
      # it won't bind until after a Pod mounts it. But it must be pre-deployed,
      # as the Pod requires it. So 'Pending' must be treated as a 'Success' state
      if storage_class&.volume_binding_mode == "WaitForFirstConsumer"
        return status == "Pending" || status == "Bound"
      end
      false
    end

    def deploy_failed?
      status == "Lost" || failure_message.present?
    end

    def failure_message
      if storage_class_name.nil? && @storage_classes.count(&:default?) > 1
        "PVC has no StorageClass specified and there are multiple StorageClasses " \
        "annotated as default. This is an invalid cluster configuration."
      end
    end

    def timeout_message
      return STANDARD_TIMEOUT_MESSAGE unless storage_class_name.present? && !storage_class
      "PVC specified a StorageClass of #{storage_class_name} but the resource does not exist"
    end

    private

    def storage_class_name
      @definition.dig("spec", "storageClassName")
    end

    def storage_class
      if storage_class_name.present?
        @storage_classes.detect { |sc| sc.name == storage_class_name }
      # storage_class_name = "" is an explicit request for no storage class
      # storage_class_name = nil is an impplicit request for default storage class
      elsif storage_class_name != ""
        @storage_classes.detect(&:default?)
      end
    end

    class StorageClass < KubernetesResource
      DEFAULT_CLASS_ANNOTATION = "storageclass.kubernetes.io/is-default-class"
      DEFAULT_CLASS_BETA_ANNOTATION = "storageclass.beta.kubernetes.io/is-default-class"

      attr_reader :name

      def initialize(definition)
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
