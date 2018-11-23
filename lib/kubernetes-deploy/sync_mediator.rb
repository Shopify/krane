# frozen_string_literal: true
module KubernetesDeploy
  class SyncMediator
    def initialize(namespace:, context:, logger:)
      @namespace = namespace
      @context = context
      @logger = logger
      clear_cache
    end

    def get_instance(kind, resource_name, raise_if_not_found: false)
      unless @cache.key?(kind)
        return request_instance(kind, resource_name, raise_if_not_found: raise_if_not_found)
      end

      cached_instance = @cache[kind].fetch(resource_name, {})
      if cached_instance.blank? && raise_if_not_found
        raise KubernetesDeploy::Kubectl::ResourceNotFoundError, "Resource does not exist (used cache for kind #{kind})"
      end
      cached_instance
    end

    def get_all(kind, selector = nil)
      fetch_by_kind(kind) unless @cache.key?(kind)
      instances = @cache.fetch(kind, {}).values
      return instances unless selector

      instances.select do |r|
        labels = r.dig("metadata", "labels") || {}
        labels >= selector
      end
    end

    def sync(resources)
      clear_cache

      dependencies = resources.flat_map { |c| c.sync_dependencies }
      kinds = (resources.map(&:kubectl_resource_type) + dependencies).compact.uniq
      kinds.each { |kind| fetch_by_kind(kind) }

      KubernetesDeploy::Concurrency.split_across_threads(resources) do |r|
        r.sync(dup)
      end
    end

    def kubectl
      @kubectl ||= Kubectl.new(namespace: @namespace, context: @context, logger: @logger, log_failure_by_default: false)
    end

    private

    def clear_cache
      @cache = {}
    end

    def request_instance(kind, iname, raise_if_not_found:)
      raw_json, _err, st = kubectl.run("get", kind, iname, "-a", "--output=json",
        raise_if_not_found: raise_if_not_found)
      st.success? ? JSON.parse(raw_json) : {}
    end

    def fetch_by_kind(kind)
      raw_json, _, st = kubectl.run("get", kind, "-a", "--output=json")
      return unless st.success?

      instances = {}
      JSON.parse(raw_json)["items"].each do |resource|
        resource_name = resource.dig("metadata", "name")
        instances[resource_name] = resource
      end
      @cache[kind] = instances
    end
  end
end
