# frozen_string_literal: true
module Krane
  class PersistentVolumeClaim < KubernetesResource
    TIMEOUT = 5.minutes

    def sync(cache)
      super
      @storage_classes = cache.get_all(::Krane::StorageK8sIo::StorageClass.group_kind).map do |sc|
        ::Krane::StorageK8sIo::StorageClass.new(
          namespace: namespace,
          context: context,
          definition: sc,
          logger: @logger,
        )
      end
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
  end
end
