# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    # Visitor that collects the ranges of ERB nodes in a document.
    # This is useful for:
    # - Determining if an HTML element contains ERB nodes (using range.from)
    # - Recording ERB tag positions for AST restoration (using the full range)
    class ErbNodeRangeCollector < ::Herb::Visitor
      # Collect ERB node ranges from a parse result
      # @rbs parse_result: ::Herb::ParseResult
      def self.collect(parse_result) #: Hash[Integer, ::Herb::Range]
        collector = new
        parse_result.visit(collector)
        collector.ranges
      end

      attr_reader :ranges #: Hash[Integer, ::Herb::Range]

      def initialize #: void
        @ranges = {}

        super
      end

      # @rbs node: ::Herb::AST::Node
      def visit_child_nodes(node) #: void
        record_range(node) if node.class.name.start_with?("Herb::AST::ERB")
        super
      end

      private

      # Record the range of an ERB node
      # @rbs node: erb_node
      def record_range(node) #: void
        range = ::Herb::Range.new(node.tag_opening.range.from, node.tag_closing.range.to)
        ranges[range.from] = range
      end
    end
  end
end
