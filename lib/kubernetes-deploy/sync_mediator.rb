# frozen_string_literal: true
module KubernetesDeploy
  class SyncMediator
    HUGE_TASK_THRESHOLD = Concurrency::MAX_THREADS * 10 # this is pretty arbitrary--we should make it less so

    def initialize(namespace:, context:, logger:)
      @namespace = namespace
      @context = context
      @logger = logger
      clear_cache
    end

    def get_instance(kind, resource_name)
      if @cache.key?(kind)
        @cache[kind].find { |r| r.dig("metadata", "name") == resource_name }
      else
        request_instance(kind, resource_name)
      end
    end

    def get_all(kind, selector = nil)
      unless @cache.key?(kind)
        list = request_list(kind)
        @cache[kind] = list if list.present?
      end
      return @cache[kind] unless selector

      @cache[kind].select do |r|
        labels = r.dig("metadata", "labels") || {}
        labels >= selector
      end
    end

    def sync(resources)
      clear_cache
      if resources.length >= HUGE_TASK_THRESHOLD
        KubernetesResource.descendants.each do |klass|
          list = request_list(klass.kind)
          @cache[klass.kind] = list if list.present?
        end
      end

      KubernetesDeploy::Concurrency.split_across_threads(resources) do |r|
        r.sync(self)
      end
    end

    def kubectl
      @kubectl ||= Kubectl.new(namespace: @namespace, context: @context, logger: @logger, log_failure_by_default: false)
    end

    private

    def clear_cache
      @cache = Hash.new { |hash, key| hash[key] = [] }
    end

    def request_instance(kind, iname)
      raw_json, _, st = kubectl.run("get", kind, iname, "-a", "--output=json")
      st.success? ? JSON.parse(raw_json) : {}
    end

    def request_list(kind)
      raw_json, _, st = kubectl.run("get", kind, "-a", "--output=json")
      st.success? ? JSON.parse(raw_json)["items"] : []
    end
  end
end
