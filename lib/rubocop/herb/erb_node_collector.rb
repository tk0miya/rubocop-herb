# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    class ErbNodeCollector < ::Herb::Visitor
      attr_reader :nodes #: Array[::Herb::AST::Node]
      attr_reader :branch_tail_nodes #: Set[::Herb::AST::Node]

      def initialize #: void
        @nodes = []
        @branch_tail_nodes = Set.new

        super
      end

      # Conditional node types whose tail expressions don't need `_ =`.
      # These are nodes where the last expression's value becomes the return value.
      # Loops (for, while, until, block) are excluded because their body's value isn't used.
      CONDITIONAL_NODE_TYPES = [
        ::Herb::AST::ERBIfNode,
        ::Herb::AST::ERBElseNode,
        ::Herb::AST::ERBUnlessNode,
        ::Herb::AST::ERBCaseNode,
        ::Herb::AST::ERBWhenNode,
        ::Herb::AST::ERBBeginNode,
        ::Herb::AST::ERBRescueNode,
        ::Herb::AST::ERBEnsureNode
      ].freeze

      # @rbs node: ::Herb::AST::Node
      def visit_child_nodes(node) #: void
        nodes << node if node.node_name.start_with?("ERB")
        mark_branch_tail(node.statements) if conditional_node?(node) && node.respond_to?(:statements)

        super
      end

      # Returns nodes with comment filtering applied.
      # Comments are filtered out when they share the same line with other ERB nodes.
      # Comparison is based on the comment's closing position (end line).
      def filtered_nodes #: Array[::Herb::AST::Node]
        filter_comments_on_same_line(nodes)
      end

      private

      # @rbs statements: Array[::Herb::AST::Node]?
      def mark_branch_tail(statements) #: void
        return unless statements

        tail = find_tail_expression(statements)
        branch_tail_nodes << tail if tail
      end

      # Recursively finds the tail output tag in statements.
      # Traverses into HTML elements to find nested ERB nodes.
      #
      # Returns nil if the last node is an execution tag (<% %>),
      # because output tags before it are not tail expressions.
      #
      # @rbs statements: Array[::Herb::AST::Node]
      def find_tail_expression(statements) #: ::Herb::AST::Node? # rubocop:disable Metrics/CyclomaticComplexity
        statements.reverse_each do |stmt|
          case stmt
          when ::Herb::AST::ERBContentNode, ::Herb::AST::ERBBlockNode
            return stmt
          when ::Herb::AST::HTMLElementNode
            # Recurse into HTML element's body
            nested = find_tail_expression(stmt.body) if stmt.respond_to?(:body) && stmt.body
            return nested if nested
          else
            # Other ERB nodes (execution tags) are not valid tails
            return nil if stmt.node_name.start_with?("ERB")
          end
        end
        nil
      end

      # @rbs nodes: Array[::Herb::AST::Node]
      def filter_comments_on_same_line(nodes) #: Array[::Herb::AST::Node]
        non_comment_start_lines = nodes.reject { |node| comment_node?(node) }
                                       .to_set { |node| node.location.start.line }

        comments_to_remove = nodes.select do |node|
          comment_node?(node) && non_comment_start_lines.include?(node.location.end.line)
        end

        nodes.reject { |node| comments_to_remove.include?(node) }
      end

      # @rbs node: ::Herb::AST::Node
      def comment_node?(node) #: bool
        return false unless node.respond_to?(:tag_opening)

        tag_opening = node.tag_opening
        tag_opening.respond_to?(:value) && tag_opening.value.start_with?("<%#")
      end

      # @rbs node: ::Herb::AST::Node
      def conditional_node?(node) #: bool
        CONDITIONAL_NODE_TYPES.any? { |type| node.is_a?(type) }
      end
    end
  end
end
