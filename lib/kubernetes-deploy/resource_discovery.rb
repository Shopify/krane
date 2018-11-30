# frozen_string_literal: true

module KubernetesDeploy
  class ResourceDiscovery
    def initialize(namespace:, context:, logger:, namespace_tags:)
      @namespace = namespace
      @context = context
      @logger = logger
      @namespace_tags = namespace_tags
    end

    def crds
      @crds ||= fetch_crds.map do |cr_def|
        CustomResourceDefinition.new(namespace: @namespace, context: @context, logger: @logger,
          definition: cr_def, statsd_tags: @namespace_tags)
      end
    end

    private

    def fetch_crds
      raw_json, _, st = kubectl.run("get", "CustomResourceDefinition", "-a", "--output=json", attempts: 5)
      if st.success?
        JSON.parse(raw_json)["items"]
      else
        []
      end
    end

    def kubectl
      @kubectl ||= Kubectl.new(namespace: @namespace, context: @context, logger: @logger, log_failure_by_default: true)
    end
  end
end
