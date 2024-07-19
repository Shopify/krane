# frozen_string_literal: true
require 'concurrent'

module Krane
  class ClusterResourceDiscovery
    delegate :namespace, :context, :logger, to: :@task_config

    def initialize(task_config:, namespace_tags: [])
      @task_config = task_config
      @namespace_tags = namespace_tags
      @api_path_cache = {}
    end

    def crds
      @crds ||= fetch_crds.map do |cr_def|
        CustomResourceDefinition.new(namespace: namespace, context: context, logger: logger,
          definition: cr_def, statsd_tags: @namespace_tags)
      end
    end

    def prunable_resources(namespaced:)
      black_list = %w(Namespace Node ControllerRevision Event)
      fetch_resources(namespaced: namespaced).map do |resource|
        next unless resource["verbs"].one? { |v| v == "delete" }
        next if black_list.include?(resource["kind"])
        [resource["apigroup"], resource["version"], resource["kind"]].compact.join("/")
      end.compact
    end

    def fetch_resources(namespaced: false)
      responses = Concurrent::Hash.new
      Krane::Concurrency.split_across_threads(api_paths) do |path|
        responses[path] = fetch_api_path(path)["resources"] || []
      end
      responses.flat_map do |path, resources|
        resources.map { |r| resource_hash(path, namespaced, r) }
      end.compact.uniq { |r| "#{r['apigroup']}/#{r['kind']}" }
    end

    private

    # During discovery, the api paths may not actually be at the root, so we must programatically find it.
    def base_api_path
      @base_api_path ||= begin
        raw_response, err, st = kubectl.run("config", "view", "--minify", "--output",
          "jsonpath={.clusters[*].cluster.server}", attempts: 5, use_namespace: false)
        raise FatalKubeAPIError, "Error retrieving cluster url: #{err}" unless st.success?

        URI(raw_response).path.blank? ? "/" : URI(raw_response).path
      end
    end

    def api_paths
      @api_path_cache["/"] ||= begin
        raw_json, err, st = kubectl.run("get", "--raw", base_api_path, attempts: 5, use_namespace: false)
        paths = if st.success?
          MultiJson.load(raw_json)["paths"]
        else
          raise FatalKubeAPIError, "Error retrieving raw path /: #{err}"
        end
        paths.select { |path| %r{^\/api.*\/v.*$}.match(path) }
      end
    end

    def fetch_api_path(path)
      @api_path_cache[path] ||= begin
        raw_json, err, st = kubectl.run("get", "--raw", base_api_path + path, attempts: 2, use_namespace: false)
        if st.success?
          MultiJson.load(raw_json)
        else
          logger.warn("Error retrieving api path: #{err}")
          {}
        end
      end
    end

    def resource_hash(path, namespaced, blob)
      return unless blob["namespaced"] == namespaced
      # skip sub-resources
      return if blob["name"].include?("/")
      path_regex = %r{(/apis?/)(?<group>[^/]*)/?(?<version>v.+)}
      match = path.match(path_regex)
      {
        "verbs" => blob["verbs"],
        "kind" => blob["kind"],
        "apigroup" => match[:group],
        "version" => match[:version],
      }
    end

    def fetch_crds
      raw_json, err, st = kubectl.run("get", "CustomResourceDefinition", output: "json", attempts: 5,
        use_namespace: false)
      if st.success?
        MultiJson.load(raw_json)["items"]
      else
        raise FatalKubeAPIError, "Error retrieving CustomResourceDefinition: #{err}"
      end
    end

    def kubectl
      @kubectl ||= Kubectl.new(task_config: @task_config, log_failure_by_default: true)
    end
  end
end
