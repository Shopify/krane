# frozen_string_literal: true
module KubernetesDeploy
  class ResourceCache
    def initialize(namespace, context, logger)
      @namespace = namespace
      @context = context
      @logger = logger

      @mutexes = Hash.new { |hash, key| hash[key] = Mutex.new }
      @data = {}
    end

    def get_instance(kind, resource_name, raise_if_not_found: false)
      instance = use_or_populate_cache(kind).fetch(resource_name, {})
      if instance.blank? && raise_if_not_found
        raise KubernetesDeploy::Kubectl::ResourceNotFoundError, "Resource does not exist (used cache for kind #{kind})"
      end
      instance
    rescue KubectlError
      {}
    end

    def get_all(kind, selector = nil)
      instances = use_or_populate_cache(kind).values
      return instances unless selector

      instances.select do |r|
        labels = r.dig("metadata", "labels") || {}
        labels >= selector
      end
    rescue KubectlError
      []
    end

    private

    def statsd_tags
      { namespace: @namespace, context: @context }
    end

    def use_or_populate_cache(kind)
      @mutexes[kind].synchronize do
        return @data.fetch(kind, {}) if @data.key?(kind)
        ::StatsD.increment("sync.cache_miss", tags: statsd_tags.merge(type: kind))
        @logger.debug("Cache miss for kind #{kind}.")
        @data[kind] = fetch_by_kind(kind)
      end
    end

    def fetch_by_kind(kind)
      raw_json, _, st = kubectl.run("get", kind, "-a", "--output=json", attempts: 5)
      raise KubectlError unless st.success?

      instances = {}
      JSON.parse(raw_json)["items"].each do |resource|
        resource_name = resource.dig("metadata", "name")
        instances[resource_name] = resource
      end
      instances
    end

    def kubectl
      @kubectl ||= Kubectl.new(namespace: @namespace, context: @context, logger: @logger, log_failure_by_default: false)
    end
  end
end
