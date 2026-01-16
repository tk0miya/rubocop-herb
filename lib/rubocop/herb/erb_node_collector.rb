# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    # Collects ERB nodes from a Herb AST, filtering out HTML nodes.
    # Preserves the hierarchical structure of ERB nodes.
    # Returns Herb::AST node instances with filtered children/statements.
    class ErbNodeCollector < ::Herb::Visitor # rubocop:disable Metrics/ClassLength
      attr_reader :result #: Array[::Herb::AST::Node]

      def initialize #: void
        @result = []

        super
      end

      # Shorthand for collecting ERB nodes from a parse result.
      # @rbs parse_result: ::Herb::ParseResult
      def self.collect(parse_result) #: Array[::Herb::AST::Node]
        collector = new
        parse_result.visit(collector)
        collector.result
      end

      # @rbs node: ::Herb::AST::ERBIfNode
      def visit_erb_if_node(node) #: void
        @result << ::Herb::AST::ERBIfNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          visit_children(node.statements),
          transform(node.subsequent),
          node.end_node
        )
      end

      # @rbs node: ::Herb::AST::ERBElseNode
      def visit_erb_else_node(node) #: void
        @result << ::Herb::AST::ERBElseNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          visit_children(node.statements)
        )
      end

      # @rbs node: ::Herb::AST::ERBUnlessNode
      def visit_erb_unless_node(node) #: void
        @result << ::Herb::AST::ERBUnlessNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          visit_children(node.statements),
          transform(node.else_clause),
          node.end_node
        )
      end

      # @rbs node: ::Herb::AST::ERBCaseNode
      def visit_erb_case_node(node) #: void
        @result << ::Herb::AST::ERBCaseNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          node.children,
          node.conditions.map { |c| transform(c) }.compact,
          transform(node.else_clause),
          node.end_node
        )
      end

      # @rbs node: ::Herb::AST::ERBWhenNode
      def visit_erb_when_node(node) #: void
        @result << ::Herb::AST::ERBWhenNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          visit_children(node.statements)
        )
      end

      # @rbs node: ::Herb::AST::ERBBeginNode
      def visit_erb_begin_node(node) #: void
        @result << ::Herb::AST::ERBBeginNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          visit_children(node.statements),
          transform(node.rescue_clause),
          transform(node.else_clause),
          transform(node.ensure_clause),
          node.end_node
        )
      end

      # @rbs node: ::Herb::AST::ERBRescueNode
      def visit_erb_rescue_node(node) #: void
        @result << ::Herb::AST::ERBRescueNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          visit_children(node.statements),
          transform(node.subsequent)
        )
      end

      # @rbs node: ::Herb::AST::ERBEnsureNode
      def visit_erb_ensure_node(node) #: void
        @result << ::Herb::AST::ERBEnsureNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          visit_children(node.statements)
        )
      end

      # @rbs node: ::Herb::AST::ERBBlockNode
      def visit_erb_block_node(node) #: void
        @result << ::Herb::AST::ERBBlockNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          visit_children(node.body),
          node.end_node
        )
      end

      # @rbs node: ::Herb::AST::ERBForNode
      def visit_erb_for_node(node) #: void
        @result << ::Herb::AST::ERBForNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          visit_children(node.statements),
          node.end_node
        )
      end

      # @rbs node: ::Herb::AST::ERBWhileNode
      def visit_erb_while_node(node) #: void
        @result << ::Herb::AST::ERBWhileNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          visit_children(node.statements),
          node.end_node
        )
      end

      # @rbs node: ::Herb::AST::ERBUntilNode
      def visit_erb_until_node(node) #: void
        @result << ::Herb::AST::ERBUntilNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          visit_children(node.statements),
          node.end_node
        )
      end

      # Terminal ERB nodes - add as-is
      # @rbs node: ::Herb::AST::ERBContentNode
      def visit_erb_content_node(node) #: void
        @result << node
      end

      # @rbs node: ::Herb::AST::ERBYieldNode
      def visit_erb_yield_node(node) #: void
        @result << node
      end

      # @rbs node: ::Herb::AST::ERBEndNode
      def visit_erb_end_node(node) #: void
        @result << node
      end

      # HTML nodes - traverse body to find nested ERB nodes
      # @rbs node: ::Herb::AST::HTMLElementNode
      def visit_html_element_node(node) #: void
        visit_all(node.body)
      end

      # Skip HTML text nodes
      # @rbs _node: ::Herb::AST::HTMLTextNode
      def visit_html_text_node(_node) #: void
        # Do nothing - skip HTML text
      end

      private

      # Visits children and returns the collected results.
      # @rbs nodes: Array[::Herb::AST::Node]
      def visit_children(nodes) #: Array[::Herb::AST::Node]
        visitor = self.class.new
        visitor.visit_all(nodes)
        visitor.result
      end

      # Transforms a single node using a sub-visitor.
      # Returns nil if the node is nil, otherwise the first result.
      # @rbs node: ::Herb::AST::Node?
      def transform(node) #: ::Herb::AST::Node?
        return nil unless node

        visitor = self.class.new
        node.accept(visitor)
        visitor.result.first
      end
    end
  end
end
