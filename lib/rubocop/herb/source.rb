# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    class Source
      include Characters

      attr_reader :code #: String
      attr_reader :path #: String
      attr_reader :line_offsets #: Array[Integer]
      attr_reader :parse_result #: ::Herb::ParseResult
      attr_reader :erb_node_ranges #: Hash[Integer, ::Herb::Range]

      # @rbs path: String
      # @rbs code: String
      def initialize(path, code) #: void
        @path = path
        @code = code
        parse
      end

      # Check if a range contains any ERB nodes
      # @rbs range: ::Herb::Range
      def contains_erb?(range) #: bool
        erb_node_ranges.keys.any? { |pos| pos >= range.from && pos < range.to }
      end

      # @rbs range: ::Herb::Range
      def byteslice(range) #: String
        code.byteslice(range.from, range.to - range.from).force_encoding(code.encoding)
      end

      def encoding #: Encoding
        code.encoding
      end

      # Convert a Herb::Location to a Herb::Range
      # @rbs location: ::Herb::Location
      def location_to_range(location) #: ::Herb::Range
        start_pos = byte_offset(location.start.line, location.start.column)
        end_pos = byte_offset(location.end.line, location.end.column)
        ::Herb::Range.new(start_pos, end_pos)
      end

      private

      def parse #: void
        @parse_result = ::Herb.parse(code)
        @erb_node_ranges = ErbNodeRangeCollector.collect(@parse_result)
        @line_offsets = compute_line_offsets
      end

      # Convert line and column (1-indexed line, 0-indexed column) to byte offset
      # @rbs line: Integer
      # @rbs column: Integer
      def byte_offset(line, column) #: Integer
        line_offsets[line - 1] + column
      end

      def compute_line_offsets #: Array[Integer]
        code.split("\n", -1)[0...-1].inject([0]) do |offsets, line|
          offsets << (offsets.last + line.bytesize + 1)
        end
      end
    end
  end
end
