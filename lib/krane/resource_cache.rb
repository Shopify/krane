# frozen_string_literal: true

require 'concurrent/hash'

module Krane
  class ResourceCache
    delegate :namespace, :context, :logger, to: :@task_config

    def initialize(task_config)
      @task_config = task_config

      @kind_fetcher_locks = Concurrent::Hash.new { |hash, key| hash[key] = Mutex.new }
      @data = Concurrent::Hash.new
      @kubectl = Kubectl.new(task_config: @task_config, log_failure_by_default: false)
    end

    def get_instance(kind, resource_name, raise_if_not_found: false)
      instance = use_or_populate_cache(kind).fetch(resource_name, {})
      if instance.blank? && raise_if_not_found
        raise Krane::Kubectl::ResourceNotFoundError, "Resource does not exist (used cache for kind #{kind})"
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

    def prewarm(resources)
      sync_dependencies = resources.flat_map { |r| r.class.const_get(:SYNC_DEPENDENCIES) }
      kinds = (resources.map(&:type) + sync_dependencies).uniq
      Krane::Concurrency.split_across_threads(kinds, max_threads: kinds.count) { |kind| get_all(kind) }
    end

    private

    def statsd_tags
      { namespace: namespace, context: context }
    end

    def use_or_populate_cache(kind)
      @kind_fetcher_locks[kind].synchronize do
        return @data[kind] if @data.key?(kind)
        @data[kind] = fetch_by_kind(kind)
      end
    end

    def fetch_by_kind(kind)
      resource_class = KubernetesResource.class_for_kind(kind)
      global_kind = @task_config.global_kinds.map(&:downcase).include?(kind.downcase)
      output_is_sensitive = resource_class.nil? ? false : resource_class::SENSITIVE_TEMPLATE_CONTENT
      raw_json, _, st = @kubectl.run("get", kind, "--chunk-size=0", attempts: 5, output: "json",
         output_is_sensitive: output_is_sensitive, use_namespace: !global_kind)
      raise KubectlError unless st.success?

      instances = {}
      JSON.parse(raw_json)["items"].each do |resource|
        resource_name = resource.dig("metadata", "name")
        instances[resource_name] = resource
      end
      instances
    end
  end
end
