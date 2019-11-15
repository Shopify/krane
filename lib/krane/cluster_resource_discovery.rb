# frozen_string_literal: true

module Krane
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

    def prunable_resources(namespaced:)
      black_list = %w(Namespace Node ControllerRevision)
      api_versions = fetch_api_versions

      fetch_resources(namespaced: namespaced).map do |resource|
        next unless resource['verbs'].one? { |v| v == "delete" }
        next if black_list.include?(resource['kind'])
        group_versions = api_versions[resource['apigroup'].to_s]
        version = version_for_kind(group_versions, resource['kind'])
        [resource['apigroup'], version, resource['kind']].compact.join("/")
      end.compact
    end

    # kubectl api-resources -o wide returns 5 columns
    # NAME SHORTNAMES APIGROUP NAMESPACED KIND VERBS
    # SHORTNAMES and APIGROUP may be blank
    # VERBS is an array
    # serviceaccounts sa <blank> true ServiceAccount [create delete deletecollection get list patch update watch]
    def fetch_resources(namespaced: false)
      command = %w(api-resources)
      command << "--namespaced=#{namespaced}"
      raw, _, st = kubectl.run(*command, output: "wide", attempts: 5,
        use_namespace: false)
      if st.success?
        rows = raw.split("\n")
        header = rows[0]
        resources = rows[1..-1]
        full_width_field_names = header.downcase.scan(/[a-z]+[\W]*/)
        cursor = 0
        fields = full_width_field_names.each_with_object({}) do |name, hash|
          start = cursor
          cursor = start + name.length
          # Last field should consume the remainder of the line
          cursor = 0 if full_width_field_names.last == name.strip
          hash[name.strip] = [start, cursor - 1]
        end
        resources.map do |resource|
          resource = fields.map { |k, (s, e)| [k.strip, resource[s..e].strip] }.to_h
          # Manually parse verbs: "[get list]" into %w(get list)
          resource["verbs"] = resource["verbs"][1..-2].split
          resource
        end
      else
        []
      end
    end

    private

    # kubectl api-versions returns a list of group/version strings e.g. autoscaling/v2beta2
    # A kind may not exist in all versions of the group.
    def fetch_api_versions
      raw, _, st = kubectl.run("api-versions", attempts: 5, use_namespace: false)
      # The "core" group is represented by an empty string
      versions = { "" => %w(v1) }
      if st.success?
        rows = raw.split("\n")
        rows.each do |group_version|
          group, version = group_version.split("/")
          versions[group] ||= []
          versions[group] << version
        end
      end
      versions
    end

    def version_for_kind(versions, kind)
      # Override list for kinds that don't appear in the lastest version of a group
      version_override = { "CronJob" => "v1beta1", "VolumeAttachment" => "v1beta1",
                           "CSIDriver" => "v1beta1", "Ingress" => "v1beta1", "CSINode" => "v1beta1" }

      pattern = /v(?<major>\d+)(?<pre>alpha|beta)?(?<minor>\d+)?/
      latest = versions.sort_by do |version|
        match = version.match(pattern)
        pre = { "alpha" => 0, "beta" => 1, nil => 2 }.fetch(match[:pre])
        [match[:major].to_i, pre, match[:minor].to_i]
      end.last
      version_override.fetch(kind, latest)
    end

    def fetch_crds
      raw_json, _, st = kubectl.run("get", "CustomResourceDefinition", output: "json", attempts: 5,
        use_namespace: false)
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
