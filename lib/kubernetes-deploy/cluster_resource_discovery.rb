# frozen_string_literal: true

module KubernetesDeploy
  class ClusterResourceDiscovery
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

    def global_resource_names
      @globals ||= fetch_globals.map do |gv|
        kind, _group = gv.split(".", 2)
        kind.singularize
      end
    end

    private

    def fetch_globals
      raw_names, _, st = kubectl.run("api-resources", "--namespaced=false", output: "name", attempts: 5)
      if st.success?
        raw_names.split("\n")
      else
        []
      end
    end

    def fetch_crds
      raw_json, _, st = kubectl.run("get", "CustomResourceDefinition", output: "json", attempts: 5)
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
