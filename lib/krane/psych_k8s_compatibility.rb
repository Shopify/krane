# frozen_string_literal: true

require 'psych'

module Psych
  module Visitors
    class K8sCompatibleYAMLTree < YAMLTree
      def visit_String(string)
        return super unless string.match?(/\A[+-]?\d+(?:\.\d+)?[eE][+-]?\d+\z/)
        @emitter.scalar(string, nil, nil, true, true, Nodes::Scalar::DOUBLE_QUOTED)
      end
    end
  end

  def self.dump_k8s_compatible(object)
    visitor = Visitors::K8sCompatibleYAMLTree.create
    visitor << object
    visitor.tree.yaml
  end

  def self.dump_stream_k8s_compatible(*objects)
    visitor = Visitors::K8sCompatibleYAMLTree.create
    objects.each do |o|
      visitor << o
    end
    visitor.tree.yaml
  end
end
