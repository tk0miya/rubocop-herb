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

      # @rbs node: ::Herb::AST::Node
      def visit_child_nodes(node) #: void
        nodes << node if node.node_name.start_with?("ERB")
        mark_branch_tail(node.statements) if node.respond_to?(:statements)

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

      # Returns the last ERB node if it's an output tag.
      # - ERBContentNode: <%= expr %>
      # - ERBBlockNode: <%= expr do %>...<% end %>
      #
      # If the last ERB node is an execution tag (<% %>), returns nil
      # because output tags before it are not tail expressions.
      #
      # @rbs statements: Array[::Herb::AST::Node]
      def find_tail_expression(statements) #: ::Herb::AST::Node?
        last_erb = statements.reverse.find { |stmt| stmt.node_name.start_with?("ERB") }

        case last_erb
        when ::Herb::AST::ERBContentNode, ::Herb::AST::ERBBlockNode
          last_erb
        end
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
    end
  end
end
