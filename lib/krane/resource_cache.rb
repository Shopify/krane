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

    def get_instance(group_kind, resource_name, raise_if_not_found: false)
      instance = use_or_populate_cache(group_kind).fetch(resource_name, {})
      if instance.blank? && raise_if_not_found
        raise Krane::Kubectl::ResourceNotFoundError, "Resource does not exist (used cache for group kind #{group_kind})"
      end
      instance
    rescue KubectlError
      {}
    end

    def get_all(group_kind, selector = nil)
      instances = use_or_populate_cache(group_kind).values
      return instances unless selector

      instances.select do |r|
        labels = r.dig("metadata", "labels") || {}
        labels >= selector
      end
    rescue KubectlError
      []
    end

    def prewarm(resources)
      sync_dependencies = resources.flat_map do |r|
        r.class.const_get(:SYNC_DEPENDENCIES).map{ |d| d.group_kind }
      end

      group_kinds = (resources.map(&:group_kind) + sync_dependencies).uniq

      Krane::Concurrency.split_across_threads(group_kinds, max_threads: group_kinds.count) { |group_kind| get_all(group_kind) }
    end

    private

    def statsd_tags
      { namespace: namespace, context: context }
    end

    def use_or_populate_cache(group_kind)
      @kind_fetcher_locks[group_kind].synchronize do
        return @data[group_kind] if @data.key?(group_kind)
        @data[group_kind] = fetch_by_group_kind(group_kind)
      end
    end

    def fetch_by_group_kind(group_kind)
      gvk = @task_config.gvk.find { |g| g["group_kind"] == group_kind }
      resource_class = ::Krane.group_kind_to_const(group_kind)

      output_is_sensitive = resource_class.nil? ? false : resource_class::SENSITIVE_TEMPLATE_CONTENT
      raw_json, _, st = @kubectl.run("get", group_kind, "--chunk-size=0", attempts: 5, output: "json",
         output_is_sensitive: output_is_sensitive, use_namespace: gvk["namespaced"])
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
