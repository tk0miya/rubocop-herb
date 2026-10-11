# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    # Utilities for the branches of conditionals and rescue written across ERB tags
    module Branches
      module_function

      # The if branch, the elsif branches and the else branch
      # @rbs node: ::Herb::AST::ERBIfNode
      def of_if(node) #: Array[branch_node]
        branches = [] #: Array[branch_node]
        branch = node #: branch_node?
        while branch
          branches << branch
          branch = branch.is_a?(::Herb::AST::ERBIfNode) ? branch.subsequent : nil
        end
        branches
      end

      # The rescue clauses and the else clause, which are the branches of rescue in the Ruby code
      # @rbs node: ::Herb::AST::ERBBeginNode | ::Herb::AST::ERBBlockNode
      def of_rescue(node) #: Array[branch_node]
        branches = [] #: Array[branch_node]
        rescue_clause = node.rescue_clause
        while rescue_clause
          branches << rescue_clause
          rescue_clause = rescue_clause.subsequent
        end
        else_clause = node.else_clause
        branches << else_clause if else_clause
        branches
      end

      # Check if the nodes contain HTML not rendered in the Ruby code (except whitespace):
      # text too short to place the marker (see RubyRenderer::TEXT_MARKER_POSITION),
      # HTML in open tags (e.g. attributes and their values) and HTML comments containing ERB
      # ERB nodes are checked recursively because their bodies (e.g. nested conditionals and blocks) are a part of
      # the branch. HTML elements are not because they are rendered and make the branch unique.
      # @rbs nodes: Array[::Herb::AST::Node]
      def unrendered_html?(nodes) #: bool
        nodes.any? { unrendered_html_node?(_1) }
      end

      # @rbs node: ::Herb::AST::Node
      def unrendered_html_node?(node) #: bool
        case node
        when ::Herb::AST::HTMLTextNode
          text = node.content.to_s
          text.match?(/\S/) && !text.match?(RubyRenderer::TEXT_MARKER_POSITION)
        when ::Herb::AST::LiteralNode
          node.content.to_s.match?(/\S/)
        when ::Herb::AST::HTMLElementNode, ::Herb::AST::WhitespaceNode
          false
        when ::Herb::AST::HTMLCommentNode
          node.children.any? { _1.type.start_with?("AST_ERB_") }
        else
          node.type.start_with?("AST_ERB_") ? unrendered_html?(node.compact_child_nodes) : true
        end
      end
    end
  end
end
