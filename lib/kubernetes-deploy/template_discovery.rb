# frozen_string_literal: true

module KubernetesDeploy
  class TemplateDiscovery
    def initialize(namespace:, context:, logger:, namespace_tags: [])
      @namespace = namespace
      @context = context
      @logger = logger
      @namespace_tags = namespace_tags
    end

    def resources(template_dir, renderer, crds)
      resources = []
      template_files = templates_from_dir(template_dir)
      renderer.render_files(template_files).each do |filename, definitions|
        definitions.each do |r_def|
          crd = crds[r_def["kind"]]&.first
          resources << build_resource(r_def, filename, crd)
        end
      end
      resources
    end

    def templates_from_dir(template_dir)
      Dir.foreach(template_dir).select do |filename|
        filename.end_with?(".yml.erb", ".yml", ".yaml", ".yaml.erb")
      end
    end

    private

    def build_resource(definition, filename, crd)
      KubernetesResource.build(
        namespace: @namespace,
        context: @context,
        logger: @logger,
        definition: definition,
        statsd_tags: @namespace_tags,
        crd: crd
      )
    rescue InvalidTemplateError => e
      e.filename ||= filename
      raise e
    end
  end
end
