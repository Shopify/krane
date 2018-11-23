# frozen_string_literal: true

require 'kubernetes-deploy/template_discovery'
module KubernetesDeploy
  class ResourceDiscovery
    def initialize(namespace:, context:, logger:, namespace_tags: [])
      @namespace = namespace
      @context = context
      @logger = logger
      @namespace_tags = namespace_tags
    end

    def from_templates(template_dir, renderer)
      template_files = TemplateDiscovery.new(template_dir).templates
      resources = []
      renderer.render_files(template_files).each do |filename, definitions|
        definitions.each { |r_def| resources << build_resource(r_def, filename) }
      end
      resources
    end

    def crds(sync_mediator)
      @crds ||= sync_mediator.get_all(CustomResourceDefinition.kind).map do |r_def|
        CustomResourceDefinition.new(namespace: @namespace, context: @context, logger: @logger,
          definition: r_def, statsd_tags: @namespace_tags)
      end
    end

    private

    def build_resource(definition, filename)
      KubernetesResource.build(
        namespace: @namespace,
        context: @context,
        logger: @logger,
        definition: definition,
        statsd_tags: @namespace_tags
      )
    rescue InvalidTemplateError => e
      e.filename ||= filename
      raise e
    end
  end
end
