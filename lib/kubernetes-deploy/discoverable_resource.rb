# frozen_string_literal: true
require 'kubernetes-deploy/kubernetes_resource'
require 'kubernetes-deploy/kubeclient_builder'
require 'erb'
require 'json'
require 'open3'

module KubernetesDeploy
  class DiscoverableResource < KubernetesResource
    extend KubernetesDeploy::KubeclientBuilder

    TRUE_VALUES = [true, 1, '1', 't', 'T', 'true', 'TRUE'].to_set
    DEPLOY_METADATA_ANNOTATION = 'kubernetes-deploy.shopify.io/metadata'

    def self.inherited(child_class)
      DiscoverableResource.child_classes.add(child_class)
    end

    def self.discover(context:, logger:, server_version:)
      logger.info("Discovering custom resources:")
      with_retries { discover_groups(context) }
      if server_version >= Gem::Version.new('1.7.0')
        kube_client = v1beta1_crd_kubeclient(context)
        with_retries { discover_crd(logger: logger, client: kube_client) }
      end
    end

    def self.discover_groups(context)
      kinds = discover_kinds(context)
      kinds.each_pair do |key, val|
        klass = get_static_class(kind: key)
        next unless klass
        klass.const_set(:GROUP, val[:group]) unless klass.constants.include?(:GROUP)
        klass.const_set(:VERSION, val[:version]) unless klass.constants.include?(:VERSION)
      end
    end

    def self.discover_kinds(context)
      kinds = {}

      # At the top level there is the core group (everything below /api/v1),
      rest_client = v1_kubeclient(context).create_rest_client
      raw_json = rest_client['v1'].get(rest_client.headers)
      resource_list = JSON.parse(raw_json)
      v1_group_version = { group: 'core', version: 'v1' }
      resource_list['resources'].map do |res|
        kind = res['kind']
        kinds[kind] = v1_group_version
      end

      # ...and the named groups (at path /apis/$NAME/$VERSION)
      rest_client = apis_kubeclient(context).create_rest_client
      raw_json = rest_client.get(rest_client.headers)
      group_list = JSON.parse(raw_json)
      group_list = group_list['groups']

      # Map out all detected kinds to their (preferred) group version
      group_list.each do |group|
        preferred_version = group['preferredVersion']['groupVersion']
        all_versions = group['versions'].map { |version| version['groupVersion'] }
        # Make sure the preferred version gets checked first.
        all_versions.delete(preferred_version)
        all_versions.unshift(preferred_version)

        # Grab kinds from all versions
        all_versions.each do |group_version|
          raw_response = rest_client[group_version].get(rest_client.headers)
          json_response = JSON.parse(raw_response)
          resources = json_response['resources']
          resources.each do |res|
            kind = res['kind']
            next if kinds.key?(kind) # Respect the preferred version
            group, _, version = group_version.rpartition('/')
            kinds[kind] = { group: group, version: version }
          end
        end
      end

      kinds
    end

    def self.build(namespace:, context:, definition:, logger:, statsd_tags:)
      opts = { namespace: namespace, context: context, definition: definition, logger: logger, statsd_tags: statsd_tags }
      kind = definition["kind"]
      group, _, version = definition['apiVersion'].rpartition('/')

      klass = get_static_class(kind: kind)
      klass = get_dynamic_class(group: group, version: version, kind: kind) unless klass
      klass.new(**opts)
    end

    def self.get_static_class(kind:)
      KubernetesDeploy.const_get(kind) if KubernetesDeploy.const_defined?(kind)
    end

    def self.get_dynamic_class(group:, version:, kind:)
      unless DiscoverableResource.const_defined?(kind)
        generate_resource(group: group, version: version, kind: kind, annotations: {})
      end
      DiscoverableResource.const_get(kind)
    end

    def self.with_retries(retries = 3, backoff = 10)
      yield
    rescue KubeException => err
      if (retries -= 1) > 0
        logger.warn("Retrying to discover CustomResourceDefinitions: #{err}")
        sleep(backoff)
        retry
      else
        logger.warn("Unable to discover CustomResourceDefinitions: #{err}")
      end
    end

    def self.discover_crd(logger:, client:)
      @child_classes = Set.new
      resources = client.get_custom_resource_definitions
      resources.each do |res|
        kind = res.spec.names.kind
        # Remove and redefine the class if it already exists so we can be up to date.
        if DiscoverableResource.const_defined?(kind)
          klass = DiscoverableResource.const_get(kind)
          DiscoverableResource.send(:remove_const, kind)
          child_classes.delete(klass)
        end
        generate_resource(group: res.spec.group,
                           version: res.spec.version,
                           kind: kind,
                           annotations: res.metadata.annotations)
        logger.info("  - #{res.spec.group}/#{res.spec.version}/#{kind}")
      end
    end

    def self.generate_resource(group:, version:, kind:, annotations:)
      deploy_metadata = annotations[DEPLOY_METADATA_ANNOTATION] || '{}'
      metadata = JSON.parse(deploy_metadata)
      unless metadata.is_a?(Hash)
        raise FatalDeploymentError, "Invalid metadata for #{kind} #{metadata.inspect}"
      end

      predeploy_dependencies = [] << metadata['predeploy-dependencies']
      predeploy_dependencies.flatten!
      predeploy_dependencies.compact!

      prunable = parse_bool(metadata['prunable'])
      predeploy = parse_bool(metadata['predeploy'])
      status_query = metadata['status-query']
      success_status = metadata['status-success']

      resource_template = ERB.new <<-CLASS
        class #{kind.capitalize} < DiscoverableResource
          GROUP = '#{group}'
          VERSION = '#{version}'
          PREDEPLOY = #{predeploy}
          PRUNABLE = #{prunable}

          <% unless predeploy_dependencies.empty? %>
          PREDEPLOY_DEPENDENCIES = #{predeploy_dependencies}
          <% end %>

          <% if status_query && success_status %>
          def deploy_succeeded?
            getter = "get_#{kind.downcase}"
            @client ||= DiscoverableResource.kubeclient(context: @context, resource_class: self.class)
            raw_json = @client.send(getter, @name, @namespace, as: :raw)
            result = query_json(query: STATUS_QUERY, json: raw_json)
            result == SUCCESS_STATUS
          end
          <% end %>

          self
        end
      CLASS

      rendered_template = resource_template.result(binding)
      klass = class_eval(rendered_template)
      klass.const_set(:STATUS_QUERY, status_query)
      klass.const_set(:SUCCESS_STATUS, success_status)
      klass
    rescue JSON::ParserError => e
      raise FatalDeploymentError, "Invalid metadata for #{group}/#{version}/#{kind}: #{e}"
    end

    def self.parse_bool(value)
      return true if TRUE_VALUES.include?(value)
      false
    end

    def query_json(query:, json:)
      safe_query = Shellwords.escape(query)
      out, err, status = Open3.capture3("jq -r #{safe_query}", stdin_data: json)
      unless status.success?
        str = "Invalid status query '#{query}' for #{self.class.qualified_kind}: #{err}"
        raise FatalDeploymentError, str
      end
      out.strip # Trailing newlines
    end

    def self.kubeclient(context:, resource_class:)
      _build_kubeclient(
        api_version: resource_class.version,
        context: context,
        endpoint_path: "/apis/#{resource_class.group}"
      )
    end

    def self.apis_kubeclient(context)
      @apis_kubeclient ||= _build_kubeclient(
        api_version: '', # The apis endpoint is not versioned
        context: context,
        endpoint_path: "/apis",
        discover: false # Will fail on apis endpoint
      )
    end

    def self.v1_kubeclient(context)
      @v1_kubeclient ||= build_v1_kubeclient(context)
    end

    def self.v1beta1_kubeclient(context)
      @v1beta1_kubeclient ||= build_v1beta1_kubeclient(context)
    end

    def self.v1beta1_crd_kubeclient(context)
      @v1beta1_kubeclient_crd ||= _build_kubeclient(
        api_version: "v1beta1",
        context: context,
        endpoint_path: "/apis/apiextensions.k8s.io/"
      )
    end
  end
end
