# frozen_string_literal: true

require 'erb'
require 'securerandom'
require 'yaml'
require 'json'

module KubernetesDeploy
  class Renderer
    class InvalidPartialError < InvalidTemplateError
      attr_accessor :parents, :content, :filename
      def initialize(msg, parents: [], content: nil, filename:)
        @parents = parents
        super(msg, content: content, filename: filename)
      end
    end
    class PartialNotFound < InvalidTemplateError; end

    def initialize(current_sha:, template_dir:, logger:, bindings: {})
      @current_sha = current_sha
      @template_dir = template_dir
      @partials_dirs =
        %w(partials ../partials).map { |d| File.expand_path(File.join(@template_dir, d)) }
      @logger = logger
      @bindings = bindings
      # Max length of podname is only 63chars so try to save some room by truncating sha to 8 chars
      @id = current_sha[0...8] + "-#{SecureRandom.hex(4)}" if current_sha
    end

    def render_files(filenames)
      files = {}
      filenames.each do |filename|
        files[filename] = split_templates(filename)
      end
      files
    end

    def render_template(filename, raw_template)
      return raw_template unless File.extname(filename) == ".erb"

      erb_binding = TemplateContext.new(self).template_binding
      bind_template_variables(erb_binding, template_variables)

      ERB.new(raw_template, nil, '-').result(erb_binding)
    rescue InvalidPartialError => err
      err.parents = err.parents.dup.unshift(filename)
      err.filename = "#{err.filename} (partial included from: #{err.parents.join(' -> ')})"
      raise err
    rescue StandardError => err
      raise InvalidTemplateError.new(err.message, filename: filename, content: raw_template)
    end

    def render_partial(partial, locals)
      variables = template_variables.merge(locals)
      erb_binding = TemplateContext.new(self).template_binding
      bind_template_variables(erb_binding, variables)
      erb_binding.local_variable_set("locals", locals)

      partial_path = find_partial(partial)
      template = File.read(partial_path)
      expanded_template = ERB.new(template, nil, '-').result(erb_binding)

      docs = Psych.parse_stream(expanded_template)
      # If the partial contains multiple documents or has an explicit document header,
      # we know it cannot validly be indented in the parent, so return it immediately.
      return expanded_template unless docs.children.one? && docs.children.first.implicit
      # Make sure indentation isn't a problem by producing a single line of parseable YAML.
      # Note that JSON is a subset of YAML.
      JSON.generate(docs.children.first.to_ruby)
    rescue PartialNotFound => err
      # get the filename from the first parent, not the missing partial itself
      raise err if err.filename == partial
      raise InvalidPartialError.new(err.message, filename: partial, content: expanded_template || template)
    rescue InvalidPartialError => err
      err.parents = err.parents.dup.unshift(File.basename(partial_path))
      raise err
    rescue StandardError => err
      raise InvalidPartialError.new(err.message, filename: partial_path, content: expanded_template || template)
    end

    private

    def split_templates(filename)
      results = []
      file_content = File.read(File.join(@template_dir, filename))
      rendered_content = render_template(filename, file_content)

      YAML.load_stream(rendered_content) do |doc|
        next if doc.blank?
        unless doc.is_a?(Hash)
          raise InvalidTemplateError.new("Template is not a valid Kubernetes manifest",
            filename: filename, content: doc)
        end
        results << doc
      end

      results
    rescue InvalidTemplateError => e
      e.filename ||= filename
      raise e
    rescue Psych::SyntaxError => e
      raise InvalidTemplateError.new("Failed to render and parse template: #{e}", filename: filename)
    end

    def template_variables
      {
        'current_sha' => @current_sha,
        'deployment_id' => @id,
      }.merge(@bindings)
    end

    def bind_template_variables(erb_binding, variables)
      variables.each do |var_name, value|
        erb_binding.local_variable_set(var_name, value)
      end
    end

    def find_partial(name)
      partial_names = [name + '.yaml.erb', name + '.yml.erb']
      @partials_dirs.each do |dir|
        partial_names.each do |partial_name|
          partial_path = File.join(dir, partial_name)
          return partial_path if File.exist?(partial_path)
        end
      end
      raise PartialNotFound.new("Could not find partial '#{name}' in any of #{@partials_dirs.join(':')}",
        filename: name)
    end

    class TemplateContext
      def initialize(renderer)
        @_renderer = renderer
      end

      def template_binding
        binding
      end

      def partial(partial, locals = {})
        @_renderer.render_partial(partial, locals)
      end
    end
  end
end
