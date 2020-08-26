# frozen_string_literal: true

require 'psych'

module PsychK8sCompatibility
  def self.massage_node(n)
    if n.is_a?(Psych::Nodes::Scalar) &&
        (n.style == Psych::Nodes::Scalar::PLAIN) &&
        n.value.is_a?(String) &&
        n.value =~ /\A[+-]?\d+(?:\.\d+)?[eE][+-]?\d+\z/
      n.style = Psych::Nodes::Scalar::DOUBLE_QUOTED
    end
  end

  refine Psych.singleton_class do
    def dump(o, io = nil, options = {})
      if io.is_a?(Hash)
        options = io
        io = nil
      end
      visitor = Psych::Visitors::YAMLTree.create(options)
      visitor << o
      visitor.tree.each { |n| PsychK8sCompatibility.massage_node(n) }
      visitor.tree.yaml(io, options)
    end

    def dump_stream(*objects)
      visitor = Psych::Visitors::YAMLTree.create({})
      objects.each do |o|
        visitor << o
      end
      visitor.tree.each { |n| PsychK8sCompatibility.massage_node(n) }
      visitor.tree.yaml
    end
  end
end
