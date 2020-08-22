# frozen_string_literal: true

require 'psych'

# PsychK8sPatch applies patching to Psych.dump/dump_stream with an alternative string serializer that is more compatible
# with Kubernetes (and other Go-based tooling). Related issue: https://github.com/Shopify/krane/issues/740
module PsychK8sPatch
  # Activate will apply the patch after creating backup aliases for the original methods.
  def self.activate
    class << Psych
      raise "Patch was already activated!" if @activated
      @activated = true
      alias_method :__orig__dump, :dump
      alias_method :__orig__dump_stream, :dump_stream

      def dump(o, io = nil, options = {})
        if io.is_a?(Hash)
          options = io
          io = nil
        end

        visitor = Psych::Visitors::YAMLTree.create(options)
        visitor << o
        visitor.tree.each { |n| PsychK8sPatch.massage_node(n) }
        visitor.tree.yaml(io, options)
      end

      def dump_stream(*objects)
        visitor = Psych::Visitors::YAMLTree.create({})
        objects.each do |o|
          visitor << o
        end
        visitor.tree.each { |n| PsychK8sPatch.massage_node(n) }
        visitor.tree.yaml
      end
    end
  end

  # Deactivate will restore the original methods from backup aliases.
  def self.deactivate
    class << Psych
      raise "Patch was not activated!" unless @activated
      @activated = false
      alias_method :dump, :__orig__dump
      alias_method :dump_stream, :__orig__dump_stream
    end
  end

  # fix_node applies DOUBLE_QUOTED style to string scalars that look like scientific/e-notation numbers.
  # This is required by YAML 1.2. Failure to do so results in Go-based tools (ie: K8s) to interpret as number!
  def self.massage_node(n)
    if n.is_a?(Psych::Nodes::Scalar) &&
        (n.style == Psych::Nodes::Scalar::PLAIN) &&
        n.value.is_a?(String) &&
        n.value =~ /\A[+-]?\d+(?:\.\d+)?[eE][+-]?\d+\z/

      n.style = Psych::Nodes::Scalar::DOUBLE_QUOTED
    end
  end
end
