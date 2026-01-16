# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    # Collects ERB nodes from a Herb AST, filtering out HTML nodes.
    # Preserves the hierarchical structure of ERB nodes.
    # Returns Herb::AST node instances with filtered children/statements.
    class ErbNodeCollector < ::Herb::Visitor # rubocop:disable Metrics/ClassLength
      attr_reader :nodes #: Array[::Herb::AST::Node]

      def initialize #: void
        @nodes = []

        super
      end

      # Shorthand for collecting ERB nodes from a parse result.
      # @rbs parse_result: ::Herb::ParseResult
      def self.collect(parse_result) #: Array[::Herb::AST::Node]
        collector = new
        parse_result.visit(collector)
        collector.nodes
      end

      # @rbs node: ::Herb::AST::ERBIfNode
      def visit_erb_if_node(node) #: void
        @nodes << ::Herb::AST::ERBIfNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          collect(node.statements),
          collect(node.subsequent).first,
          node.end_node
        )
      end

      # @rbs node: ::Herb::AST::ERBElseNode
      def visit_erb_else_node(node) #: void
        @nodes << ::Herb::AST::ERBElseNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          collect(node.statements)
        )
      end

      # @rbs node: ::Herb::AST::ERBUnlessNode
      def visit_erb_unless_node(node) #: void
        @nodes << ::Herb::AST::ERBUnlessNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          collect(node.statements),
          collect(node.else_clause).first,
          node.end_node
        )
      end

      # @rbs node: ::Herb::AST::ERBCaseNode
      def visit_erb_case_node(node) #: void
        @nodes << ::Herb::AST::ERBCaseNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          node.children,
          node.conditions.map { |c| collect(c).first }.compact,
          collect(node.else_clause).first,
          node.end_node
        )
      end

      # @rbs node: ::Herb::AST::ERBWhenNode
      def visit_erb_when_node(node) #: void
        @nodes << ::Herb::AST::ERBWhenNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          collect(node.statements)
        )
      end

      # @rbs node: ::Herb::AST::ERBBeginNode
      def visit_erb_begin_node(node) #: void
        @nodes << ::Herb::AST::ERBBeginNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          collect(node.statements),
          collect(node.rescue_clause).first,
          collect(node.else_clause).first,
          collect(node.ensure_clause).first,
          node.end_node
        )
      end

      # @rbs node: ::Herb::AST::ERBRescueNode
      def visit_erb_rescue_node(node) #: void
        @nodes << ::Herb::AST::ERBRescueNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          collect(node.statements),
          collect(node.subsequent).first
        )
      end

      # @rbs node: ::Herb::AST::ERBEnsureNode
      def visit_erb_ensure_node(node) #: void
        @nodes << ::Herb::AST::ERBEnsureNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          collect(node.statements)
        )
      end

      # @rbs node: ::Herb::AST::ERBBlockNode
      def visit_erb_block_node(node) #: void
        @nodes << ::Herb::AST::ERBBlockNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          collect(node.body),
          node.end_node
        )
      end

      # @rbs node: ::Herb::AST::ERBForNode
      def visit_erb_for_node(node) #: void
        @nodes << ::Herb::AST::ERBForNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          collect(node.statements),
          node.end_node
        )
      end

      # @rbs node: ::Herb::AST::ERBWhileNode
      def visit_erb_while_node(node) #: void
        @nodes << ::Herb::AST::ERBWhileNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          collect(node.statements),
          node.end_node
        )
      end

      # @rbs node: ::Herb::AST::ERBUntilNode
      def visit_erb_until_node(node) #: void
        @nodes << ::Herb::AST::ERBUntilNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          collect(node.statements),
          node.end_node
        )
      end

      # Terminal ERB nodes - add as-is
      # @rbs node: ::Herb::AST::ERBContentNode
      def visit_erb_content_node(node) #: void
        @nodes << node
      end

      # @rbs node: ::Herb::AST::ERBYieldNode
      def visit_erb_yield_node(node) #: void
        @nodes << node
      end

      # @rbs node: ::Herb::AST::ERBEndNode
      def visit_erb_end_node(node) #: void
        @nodes << node
      end

      private

      # Collects ERB nodes from given nodes using a sub-collector.
      # Accepts an array or a single node.
      # @rbs nodes: Array[::Herb::AST::Node] | ::Herb::AST::Node | nil
      def collect(nodes) #: Array[::Herb::AST::Node]
        collector = self.class.new
        collector.visit_all(Array(nodes).compact)
        collector.nodes
      end
    end
  end
end
