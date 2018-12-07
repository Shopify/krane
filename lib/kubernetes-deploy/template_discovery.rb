# frozen_string_literal: true

module KubernetesDeploy
  class TemplateDiscovery
    def initialize(template_dir)
      @template_dir = template_dir
    end

    def templates
      Dir.foreach(@template_dir).select do |filename|
        filename.end_with?(".yml.erb", ".yml", ".yaml", ".yaml.erb")
      end
    end
  end
end
