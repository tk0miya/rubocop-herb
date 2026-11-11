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
      # text and literals too short to place the marker (see RubyRenderer.text_marker_position)
      # and attributes in ERB nodes none of whose literals fit the marker (see RubyRenderer#visit_html_attribute_node)
      # ERB nodes are checked recursively because their bodies (e.g. nested conditionals and blocks) are a part of
      # the branch. HTML elements, tags, comments, doctypes, CDATA and XML declarations, and the attributes rendered
      # as markers are not because they are rendered as markers and make the branch unique.
      # @rbs nodes: Array[::Herb::AST::Node]
      def unrendered_html?(nodes) #: bool
        nodes.any? { unrendered_html_node?(_1) }
      end

      # @rbs node: ::Herb::AST::Node
      def unrendered_html_node?(node) #: bool
        case node
        when ::Herb::AST::HTMLTextNode, ::Herb::AST::LiteralNode
          unrendered_text?(node.content.to_s)
        when ::Herb::AST::HTMLElementNode, ::Herb::AST::HTMLOpenTagNode, ::Herb::AST::HTMLCloseTagNode,
             ::Herb::AST::HTMLCommentNode, ::Herb::AST::HTMLDoctypeNode, ::Herb::AST::CDATANode,
             ::Herb::AST::XMLDeclarationNode, ::Herb::AST::WhitespaceNode
          false
        when ::Herb::AST::HTMLAttributeNode
          unrendered_attribute?(node)
        else
          node.type.start_with?("AST_ERB_") ? unrendered_html?(node.compact_child_nodes) : true
        end
      end

      # @rbs text: String
      def unrendered_text?(text) #: bool
        text.match?(/\S/) && !RubyRenderer.text_marker_position(text)
      end

      # Check if the attribute in an ERB node has no literal to place the marker in
      # (e.g. `id="ab"` and `<%= k %>="<%= v %>"`), as it is rendered at one of its literals
      # @rbs node: ::Herb::AST::HTMLAttributeNode
      def unrendered_attribute?(node) #: bool
        children = [*node.name&.children, *node.value&.children] #: Array[::Herb::AST::Node]
        children.none? { _1.is_a?(::Herb::AST::LiteralNode) && RubyRenderer.text_marker_position(_1.content.to_s) }
      end
    end
  end
end
