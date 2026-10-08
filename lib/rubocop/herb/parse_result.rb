# frozen_string_literal: true

require "forwardable"
require "herb"

module RuboCop
  module Herb
    # Data class holding the results of parsing an ERB file.
    # Contains the parsed AST, collected ERB locations, and precomputed data
    # needed for rendering. Logic is minimal - mostly data access and simple queries.
    ParseResult = Data.define(
      :source,                #: Source
      :ast,                   #: ::Herb::ParseResult
      :erb_locations,         #: Hash[Integer, ErbLocation]
      :erb_max_columns,       #: Hash[Integer, Integer]
      :html_block_positions,  #: Set[::Herb::AST::HTMLElementNode]
      :tail_expressions,      #: Set[::Herb::AST::Node]
      :tags,                  #: Hash[Integer, Tag]
      :disabled_cops          #: Hash[String, Array[Range[Integer]]] -- line ranges where each cop is disabled
    )

    # Methods are defined by reopening the class (not in a Data.define block)
    # so that rbs-inline can generate their type signatures.
    class ParseResult
      extend Forwardable

      # @rbs!
      #   def code: () -> String
      #   def byteslice: (::Herb::Range) -> String
      #   def slice: (CharRange range) -> String

      def_delegators :source, :code, :byteslice, :slice

      # Check if a range contains any ERB nodes
      # @rbs range: CharRange
      def contains_erb?(range) #: bool
        erb_locations.keys.any? { _1 >= range.from && _1 < range.to }
      end

      # Get all ERB comment nodes
      def erb_comment_nodes #: Array[::Herb::AST::ERBContentNode]
        erb_locations.values.select(&:comment?).filter_map do |loc|
          node = loc.node
          node if node.is_a?(::Herb::AST::ERBContentNode)
        end
      end

      # Check if a node is a tail expression (output node at end of returning block)
      # @rbs node: ::Herb::AST::Node
      def tail_expression?(node) #: bool
        tail_expressions.include?(node)
      end

      # Check if a range contains HTML content (non-whitespace characters outside ERB tags)
      # @rbs range: CharRange
      def contains_html?(range) #: bool
        tag_ranges = erb_tag_ranges
        code[range.from...range.to].to_s.each_char.with_index(range.from).any? do |char, pos|
          char.match?(/\S/) && tag_ranges.none? { _1.from <= pos && pos < _1.to }
        end
      end

      private

      # Get the ranges of ERB tags (from `<%` to `%>`)
      def erb_tag_ranges #: Array[CharRange]
        erb_locations.values.map do |location|
          node = location.node #: erb_node
          opening = source.location_to_range(node.tag_opening.not_nil!.location)
          closing = source.location_to_range(node.tag_closing.not_nil!.location)
          NodeRange.byte_range_to_char_range(::Herb::Range.new(opening.from, closing.to), source)
        end
      end
    end
  end
end
