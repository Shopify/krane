# frozen_string_literal: true
module KubernetesDeploy
  class SyncMediator
    LARGE_BATCH_THRESHOLD = Concurrency::MAX_THREADS * 3

    def initialize(namespace:, context:, logger:)
      @namespace = namespace
      @context = context
      @logger = logger
      clear_cache
    end

    def get_instance(kind, resource_name)
      if @cache.key?(kind)
        @cache.dig(kind, resource_name) || {}
      else
        request_instance(kind, resource_name)
      end
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

      if resources.count > LARGE_BATCH_THRESHOLD
        dependencies = resources.map(&:class).uniq.flat_map do |c|
          c::SYNC_DEPENDENCIES if c.const_defined?('SYNC_DEPENDENCIES')
        end
        kinds = (resources.map(&:type) + dependencies).compact.uniq
        kinds.each { |kind| fetch_by_kind(kind) }
      end

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

    def request_instance(kind, iname)
      raw_json, _, st = kubectl.run("get", kind, iname, "-a", "--output=json")
      st.success? ? JSON.parse(raw_json) : {}
    end

    def fetch_by_kind(kind)
      raw_json, _, st = kubectl.run("get", kind, "-a", "--output=json")
      return unless st.success?
      @cache[kind] = JSON.parse(raw_json)["items"].each_with_object({}) do |r, instances|
        instances[r.dig("metadata", "name")] = r
      end
    end
  end
end
