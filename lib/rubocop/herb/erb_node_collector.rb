# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    class ErbNodeCollector < ::Herb::Visitor
      attr_reader :nodes #: Array[::Herb::AST::Node]

      def initialize #: void
        @nodes = []

        super
      end

      # @rbs node: ::Herb::AST::Node
      def visit_child_nodes(node) #: void
        nodes << node if node.node_name.start_with?("ERB")

        super
      end
    end
  end
end
