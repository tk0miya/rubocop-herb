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
      #   def encoding: () -> Encoding
      def_delegators :code, :encoding

      attr_reader :code #: String
      attr_reader :path #: String
      attr_reader :ast #: ::Herb::ParseResult
      attr_reader :erb_locations #: Hash[Integer, ErbLocation]
      attr_reader :erb_max_columns #: Hash[Integer, Integer]
      attr_reader :line_offsets #: Array[Integer]
      attr_reader :html_block_positions #: Set[Integer]

      # @rbs path: String
      # @rbs code: String
      # @rbs ast: ::Herb::ParseResult
      # @rbs erb_locations: Hash[Integer, ErbLocation]
      # @rbs erb_max_columns: Hash[Integer, Integer]
      # @rbs line_offsets: Array[Integer]
      # @rbs html_block_positions: Set[Integer]
      def initialize( #: void
        path:, code:, ast:, erb_locations:, erb_max_columns:, line_offsets:, html_block_positions: Set.new
      )
        @path = path
        @code = code
        @ast = ast
        @erb_locations = erb_locations
        @erb_max_columns = erb_max_columns
        @line_offsets = line_offsets
        @html_block_positions = html_block_positions
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

      # @rbs range: ::Herb::Range
      def byteslice(range) #: String
        code.byteslice(range.from, range.to - range.from).force_encoding(code.encoding)
      end

      # Convert a Herb::Location to a Herb::Range
      # @rbs location: ::Herb::Location
      def location_to_range(location) #: ::Herb::Range
        start_pos = byte_offset(location.start.line, location.start.column)
        end_pos = byte_offset(location.end.line, location.end.column)
        ::Herb::Range.new(start_pos, end_pos)
      end

      private

      # Convert line and column to byte offset
      # Handles multi-byte characters correctly by converting character column to byte offset
      # @rbs line: Integer -- 1-indexed line number
      # @rbs column: Integer -- 0-indexed character-based column (not byte-based)
      def byte_offset(line, column) #: Integer
        line_start = line_offsets[line - 1]
        next_line_start = line_offsets[line] || code.bytesize
        line_content = code.byteslice(line_start, next_line_start - line_start)
        line_start + line_content.chars[0, column].join.bytesize
      end
    end
  end
end
