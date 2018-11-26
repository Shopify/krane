# frozen_string_literal: true

module KubernetesDeploy
  class ResourceDiscovery
    def initialize(namespace:, context:, logger:, namespace_tags:)
      @namespace = namespace
      @context = context
      @logger = logger
      @namespace_tags = namespace_tags
      @cache = ResourceCache.new(namespace, context, logger)
    end

    def crds
      @crds ||= @cache.get_all(CustomResourceDefinition.kind).map do |r_def|
        CustomResourceDefinition.new(namespace: @namespace, context: @context, logger: @logger,
          definition: r_def, statsd_tags: @namespace_tags)
      end
    end
  end
end
