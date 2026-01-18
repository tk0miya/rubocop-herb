# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    # Visitor that collects the start byte positions of ERB nodes in a document.
    # This is useful for determining if an HTML element contains ERB nodes.
    class ErbNodePositionCollector < ::Herb::Visitor
      # Collect ERB node start positions from a parse result
      # @rbs parse_result: ::Herb::ParseResult
      def self.collect(parse_result) #: Set[Integer]
        collector = new
        parse_result.visit(collector)
        collector.positions
      end

      attr_reader :positions #: Set[Integer]

      def initialize #: void
        @positions = Set.new

        super
      end

      # @rbs node: ::Herb::AST::Node
      def visit_child_nodes(node) #: void
        record_position(node) if node.class.name.start_with?("Herb::AST::ERB")
        super
      end

      private

      # Record the start byte position of an ERB node using tag_opening.range.from
      # @rbs node: ::Herb::AST::Node
      def record_position(node) #: void
        positions.add(node.tag_opening.range.from)
      end
    end
  end
end
