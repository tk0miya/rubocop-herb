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

      # Returns nodes with comment filtering applied.
      # Comments are filtered out when they share the same line with other ERB nodes.
      # Comparison is based on the comment's closing position (end line).
      def filtered_nodes #: Array[::Herb::AST::Node]
        filter_comments_on_same_line(nodes)
      end

      private

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
