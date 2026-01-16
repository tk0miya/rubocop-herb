# frozen_string_literal: true

module RuboCop
  module Herb
    # Represents an ERB-only AST extracted from Herb AST.
    # HTML nodes are filtered out, keeping only ERB nodes in a hierarchical structure.
    module ErbAst
      # Represents an ERB node in the simplified AST.
      # Each node contains children (nested ERB nodes) with HTML nodes filtered out.
      class Node
        attr_reader :herb_node #: ::Herb::AST::Node
        attr_reader :children #: Array[Node]

        # @rbs herb_node: ::Herb::AST::Node
        # @rbs children: Array[Node]
        def initialize(herb_node, children = []) #: void
          @herb_node = herb_node
          @children = children
        end

        def tag_opening #: ::Herb::AST::Node
          herb_node.tag_opening
        end

        def content #: ::Herb::AST::Node
          herb_node.content
        end

        def output_node? #: bool
          tag_opening.value == "<%="
        end

        def comment_node? #: bool
          tag_opening.value == "<%#"
        end

        # Returns the last child ERB node, or nil if no children.
        def last_child #: Node?
          children.last
        end

        # Checks if this node is the last child of its parent's children array.
        # This is useful for determining if an output node is at the tail of a branch.
        # @rbs siblings: Array[Node]
        def last_among?(siblings) #: bool
          siblings.last.equal?(self)
        end
      end
    end
  end
end
