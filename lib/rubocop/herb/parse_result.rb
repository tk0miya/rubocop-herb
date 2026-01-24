# frozen_string_literal: true

require "forwardable"
require "herb"

module RuboCop
  module Herb
    # Data class holding the results of parsing an ERB file.
    # Contains the parsed AST, collected ERB locations, and precomputed data
    # needed for rendering. Logic is minimal - mostly data access and simple queries.
    class ParseResult
      extend Forwardable
      include Characters

      # @rbs!
      #   def path: () -> String
      #   def code: () -> String
      #   def line_offsets: () -> Array[Integer]
      #   def encoding: () -> Encoding
      #   def byteslice: (::Herb::Range | ::Herb::Location) -> String
      #   def location_to_range: (::Herb::Location location) -> ::Herb::Range
      #   def char_to_byte_pos: (Integer char_pos) -> Integer
      def_delegators :source, :path, :code, :line_offsets, :encoding, :byteslice, :location_to_range,
                     :char_to_byte_pos

      attr_reader :source #: Source
      attr_reader :ast #: ::Herb::ParseResult
      attr_reader :erb_locations #: Hash[Integer, ErbLocation]
      attr_reader :erb_max_columns #: Hash[Integer, Integer]
      attr_reader :html_block_positions #: Set[Integer]
      attr_reader :tail_expressions #: Set[Integer]
      attr_reader :tags #: Hash[Integer, Tag]

      # @rbs source: Source
      # @rbs ast: ::Herb::ParseResult
      # @rbs erb_locations: Hash[Integer, ErbLocation]
      # @rbs erb_max_columns: Hash[Integer, Integer]
      # @rbs html_block_positions: Set[Integer]
      # @rbs tail_expressions: Set[Integer]
      # @rbs tags: Hash[Integer, Tag]
      def initialize(source:, ast:, erb_locations:, erb_max_columns:, #: void
                     html_block_positions:, tail_expressions:, tags:)
        @source = source
        @ast = ast
        @erb_locations = erb_locations
        @erb_max_columns = erb_max_columns
        @html_block_positions = html_block_positions
        @tail_expressions = tail_expressions
        @tags = tags
      end

      # Check if a range contains any ERB nodes
      # @rbs range: ::Herb::Range
      def contains_erb?(range) #: bool
        erb_locations.keys.any? { |pos| pos >= range.from && pos < range.to }
      end

      # Get all ERB comment nodes
      def erb_comment_nodes #: Array[::Herb::AST::ERBContentNode]
        erb_locations.values.select(&:comment?).map(&:node)
      end

      # Check if a node is a tail expression (output node at end of returning block)
      # @rbs node: ::Herb::AST::Node
      def tail_expression?(node) #: bool
        tail_expressions.include?(node.tag_opening.range.from)
      end
    end
  end
end
