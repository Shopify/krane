# frozen_string_literal: true
module KubernetesDeploy
  class PersistentVolumeClaim < KubernetesResource
    TIMEOUT = 5.minutes

    def init_storage_class(cache)
      @storage_class = {}

      if @definition.dig("spec", "storageClassName").nil?
        # if no storage class is defined we try to find the default one
        # FIXME: This assumes the DefaultStorageClass admission plugin is turned on,
        # need a way to determine this
        is_default_class = "storageclass.beta.kubernetes.io/is-default-class"

        default_sc = cache.get_all("StorageClass").select do |sc|
          sc.dig("metadata", "annotations", is_default_class) == "true"
        end

        if default_sc.length != 1
          warn_msg = "Multiple default StorageClasses found. If the DefaultStorageClass " \
            "admission plugin is turned on, all PVC creation will fail."
          @logger.warn(warn_msg) if default_sc.length > 1
          return
        else
          # using default storage class
          sc_name = default_sc[0]["metadata"]["name"]
        end
      else
        # using storage class from pvc definition
        sc_name = @definition.dig("spec", "storageClassName")

        # a storageClassName of "" is an explicit way of saying you want a PV
        # with no defined StorageClass. We won't look up a storage_class
        # if that is the case
        return if sc_name == ""
      end

      @storage_class = cache.get_instance("StorageClass", sc_name)

      # check the defined StorageClass exists
      warn_msg = "StorageClass/#{sc_name} not found. This is required for #{id} to deploy."
      @logger.warn(warn_msg) if @storage_class.blank?
    end

    def sync(cache)
      super

      # find the storage class (if we haven't already)
      init_storage_class(cache) if @storage_class.nil?
    end

    def status
      exists? ? @instance_data["status"]["phase"] : "Not Found"
    end

    def deploy_succeeded?
      # if the StorageClass has volumeBindingMode: WaitForFirstConsumer,
      # it won't bind until after a Pod mounts it. But it must be pre-deployed,
      # as the Pod requires it. So 'Pending' must be treated as a 'Success' state

      if @storage_class["volumeBindingMode"] == "WaitForFirstConsumer"
        status == "Pending" || status == "Bound"
      else
        status == "Bound"
      end
    end

    def deploy_failed?
      status == "Lost"
    end
  end
end
