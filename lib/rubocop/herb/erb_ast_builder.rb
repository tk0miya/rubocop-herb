# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    # Builds a filtered ERB AST from a Herb AST by extracting only ERB nodes.
    # HTML nodes are filtered out, preserving the hierarchical structure.
    # Returns Herb::AST node instances with filtered children/statements.
    class ErbAstBuilder < ::Herb::Visitor # rubocop:disable Metrics/ClassLength
      # Builds an array of Herb AST nodes from a parse result with HTML filtered out.
      # @rbs parse_result: ::Herb::ParseResult
      def build(parse_result) #: Array[::Herb::AST::Node]
        visit_statements(parse_result.value.children)
      end

      # @rbs node: ::Herb::AST::ERBIfNode
      def visit_erb_if_node(node) #: ::Herb::AST::ERBIfNode
        ::Herb::AST::ERBIfNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          visit_statements(node.statements),
          visit(node.subsequent),
          node.end_node
        )
      end

      # @rbs node: ::Herb::AST::ERBElseNode
      def visit_erb_else_node(node) #: ::Herb::AST::ERBElseNode
        ::Herb::AST::ERBElseNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          visit_statements(node.statements)
        )
      end

      # @rbs node: ::Herb::AST::ERBUnlessNode
      def visit_erb_unless_node(node) #: ::Herb::AST::ERBUnlessNode
        ::Herb::AST::ERBUnlessNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          visit_statements(node.statements),
          visit(node.else_clause),
          node.end_node
        )
      end

      # @rbs node: ::Herb::AST::ERBCaseNode
      def visit_erb_case_node(node) #: ::Herb::AST::ERBCaseNode
        ::Herb::AST::ERBCaseNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          node.children,
          node.conditions.map { |c| visit(c) },
          visit(node.else_clause),
          node.end_node
        )
      end

      # @rbs node: ::Herb::AST::ERBWhenNode
      def visit_erb_when_node(node) #: ::Herb::AST::ERBWhenNode
        ::Herb::AST::ERBWhenNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          visit_statements(node.statements)
        )
      end

      # @rbs node: ::Herb::AST::ERBBeginNode
      def visit_erb_begin_node(node) #: ::Herb::AST::ERBBeginNode
        ::Herb::AST::ERBBeginNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          visit_statements(node.statements),
          visit(node.rescue_clause),
          visit(node.else_clause),
          visit(node.ensure_clause),
          node.end_node
        )
      end

      # @rbs node: ::Herb::AST::ERBRescueNode
      def visit_erb_rescue_node(node) #: ::Herb::AST::ERBRescueNode
        ::Herb::AST::ERBRescueNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          visit_statements(node.statements),
          visit(node.subsequent)
        )
      end

      # @rbs node: ::Herb::AST::ERBEnsureNode
      def visit_erb_ensure_node(node) #: ::Herb::AST::ERBEnsureNode
        ::Herb::AST::ERBEnsureNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          visit_statements(node.statements)
        )
      end

      # @rbs node: ::Herb::AST::ERBBlockNode
      def visit_erb_block_node(node) #: ::Herb::AST::ERBBlockNode
        ::Herb::AST::ERBBlockNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          visit_statements(node.body),
          node.end_node
        )
      end

      # @rbs node: ::Herb::AST::ERBForNode
      def visit_erb_for_node(node) #: ::Herb::AST::ERBForNode
        ::Herb::AST::ERBForNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          visit_statements(node.statements),
          node.end_node
        )
      end

      # @rbs node: ::Herb::AST::ERBWhileNode
      def visit_erb_while_node(node) #: ::Herb::AST::ERBWhileNode
        ::Herb::AST::ERBWhileNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          visit_statements(node.statements),
          node.end_node
        )
      end

      # @rbs node: ::Herb::AST::ERBUntilNode
      def visit_erb_until_node(node) #: ::Herb::AST::ERBUntilNode
        ::Herb::AST::ERBUntilNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          visit_statements(node.statements),
          node.end_node
        )
      end

      # Terminal ERB nodes - return as-is
      # @rbs node: ::Herb::AST::ERBContentNode
      def visit_erb_content_node(node) #: ::Herb::AST::ERBContentNode
        node
      end

      # @rbs node: ::Herb::AST::ERBYieldNode
      def visit_erb_yield_node(node) #: ::Herb::AST::ERBYieldNode
        node
      end

      # @rbs node: ::Herb::AST::ERBEndNode
      def visit_erb_end_node(node) #: ::Herb::AST::ERBEndNode
        node
      end

      # HTML nodes - traverse body but don't include the node itself
      # @rbs node: ::Herb::AST::HTMLElementNode
      def visit_html_element_node(node) #: Array[::Herb::AST::Node]
        visit_statements(node.body)
      end

      # Skip HTML text nodes
      # @rbs _node: ::Herb::AST::HTMLTextNode
      def visit_html_text_node(_node) #: nil
        nil
      end

      # Default: try to visit child nodes
      # @rbs node: ::Herb::AST::Node
      def visit_child_nodes(node) #: Array[::Herb::AST::Node]
        visit_statements(node.child_nodes)
      end

      private

      # Visits an array of nodes and filters out nil values and flattens arrays.
      # @rbs nodes: Array[::Herb::AST::Node]
      def visit_statements(nodes) #: Array[::Herb::AST::Node]
        nodes.flat_map { |node| visit(node) }.compact
      end
    end
  end
end
