# frozen_string_literal: true

require 'psych'

# Monkey-patching Psych.dump with an alternative string serializer that tweaks scalar style for compatibility reasons.
module Psych
  class << self
    def dump(o, io = nil, options = {})
      if io.is_a?(Hash)
        options = io
        io = nil
      end

      puts "Psych.dump called"
      visitor = Psych::Visitors::YAMLTree.create(options)
      visitor << o
      visitor.tree.each { |n| fix_node(n) }
      visitor.tree.yaml(io, options)
    end

    def fix_node(n)
      # String scalars that looks like e-notation floats must be quoted.
      if n.is_a?(Psych::Nodes::Scalar) &&
          (n.style == Psych::Nodes::Scalar::PLAIN) &&
          n.value.is_a?(String) &&
          n.value =~ /\A[+-]?\d+(?:\.\d+)?[eE][+-]?\d+\z/

        n.style = Psych::Nodes::Scalar::DOUBLE_QUOTED
      end
    end
  end
end
