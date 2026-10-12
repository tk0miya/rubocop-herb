# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    # Mixin for Herb visitors that calls visit_escaped_erb_node instead of the visit method of the ERB node
    # for escaped ERB tags (see ErbNode.escaped?). By default it visits their children.
    # @rbs module-self ::Herb::Visitor
    module EscapedErbVisitor
      # @rbs node: ::Herb::AST::Node
      def visit_child_nodes(node) #: void
        node.compact_child_nodes.each do |child|
          if ErbNode.escaped?(child)
            visit_escaped_erb_node(child)
          else
            child.accept(self)
          end
        end
      end

      # @rbs node: ::Herb::AST::Node
      def visit_escaped_erb_node(node) #: void
        visit_child_nodes(node)
      end
    end
  end
end
