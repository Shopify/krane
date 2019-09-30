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
      @globals ||= fetch_globals.map { |g| g["kind"] }
    end

    private

    def fetch_globals
      raw, _, st = kubectl.run("api-resources", "--namespaced=false", output: "wide", attempts: 5)
      if st.success?
        rows = raw.split("\n")
        header = rows.shift.downcase.scan(/[a-z]+[\W]*/).each_with_object({}) do |match, hash|
          start = hash.values.map(&:last).max.to_i
          hash[match.strip] = [start, start + match.length]
        end
        rows.map { |r| header.map { |k, (s, e)| [k.strip, r[s...e].strip] }.to_h }
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
