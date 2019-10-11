# frozen_string_literal: true

module KubernetesDeploy
  class ClusterResourceDiscovery
    delegate :namespace, :context, :logger, to: :@task_config

    def initialize(task_config:, namespace_tags: [])
      @task_config = task_config
      @namespace_tags = namespace_tags
    end

    def crds
      @crds ||= fetch_crds.map do |cr_def|
        CustomResourceDefinition.new(namespace: namespace, context: context, logger: logger,
          definition: cr_def, statsd_tags: @namespace_tags)
      end
    end

    def global_resources
      @globals ||= fetch_globals
    end

    def api_versions
      @api_version ||= fetch_api_versions
    end

    private

    def fetch_api_versions
      raw, _, st = kubectl.run("api-versions", attempts: 5, use_namespace: false)
      if st.success?
        rows = raw.split("\n")
        rows.each_with_object({}) do |group_version, hash|
          group, version = group_version.split("/")
          hash[group] ||= []
          hash[group] << version
        end
      else
        {}
      end
    end

    def fetch_globals
      raw, _, st = kubectl.run("api-resources", "--namespaced=false", output: "wide",
        attempts: 5, use_namespace: false)
      if st.success?
        rows = raw.split("\n")
        header = rows[0]
        resources = rows[1..-1]
        full_width_field_names = header.downcase.scan(/[a-z]+[\W]*/)
        cursor = 0
        fields = full_width_field_names.each_with_object({}) do |name, hash|
          start = cursor
          cursor = start + name.length
          cursor = 0 if full_width_field_names.last == name.strip
          hash[name.strip] = [start, cursor - 1]
        end
        resources.map { |r| fields.map { |k, (s, e)| [k.strip, r[s..e].strip] }.to_h }
      else
        []
      end
    end

    def fetch_crds
      raw_json, _, st = kubectl.run("get", "CustomResourceDefinition", output: "json",
        attempts: 5, use_namespace: false)
      if st.success?
        JSON.parse(raw_json)["items"]
      else
        []
      end
    end

    def kubectl
      @kubectl ||= Kubectl.new(task_config: @task_config, log_failure_by_default: true)
    end
  end
end
