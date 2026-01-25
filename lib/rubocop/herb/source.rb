# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    # Encapsulates source code and line offset information.
    # Provides methods for byteslice and location-to-range conversion
    # that are shared between ParseResult and NodeLocationCollector.
    class Source
      attr_reader :path #: String
      attr_reader :code #: String
      attr_reader :line_offsets #: Array[Integer]

      # @rbs path: String
      # @rbs code: String
      def initialize(path:, code:) #: void
        @path = path
        @code = code
        @line_offsets = compute_line_offsets(code)
      end

      # Get the encoding of the source code
      def encoding #: Encoding
        code.encoding
      end

      # Get a substring by character range
      # @rbs char_from: Integer -- start character position
      # @rbs char_to: Integer -- end character position
      def slice(char_from, char_to) #: String
        code[char_from...char_to]
      end

      # Get a substring by byte range or location
      # @rbs range_or_location: ::Herb::Range | ::Herb::Location
      def byteslice(range_or_location) #: String
        range = range_or_location.is_a?(::Herb::Range) ? range_or_location : location_to_range(range_or_location)
        code.byteslice(range.from, range.to - range.from).force_encoding(code.encoding)
      end

      # Convert character position to byte position
      # This is needed because Parser gem uses character positions while Herb uses byte positions
      # @rbs char_pos: Integer
      def char_to_byte_pos(char_pos) #: Integer
        code[0...char_pos].bytesize
      end

      # Convert byte position to character position
      # This is needed to convert Herb's byte positions to character positions for RuboCop
      # @rbs byte_pos: Integer
      def byte_to_char_pos(byte_pos) #: Integer
        code.byteslice(0, byte_pos).length
      end

      # Convert a byte-based Herb::Range to character positions [from, to]
      # @rbs byte_range: ::Herb::Range
      def byte_range_to_char_range(byte_range) #: [Integer, Integer]
        [byte_to_char_pos(byte_range.from), byte_to_char_pos(byte_range.to)]
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

      # Compute line offsets for the source code
      # @rbs code: String
      def compute_line_offsets(code) #: Array[Integer]
        code.split("\n", -1)[0...-1].inject([0]) do |offsets, line|
          offsets << (offsets.last + line.bytesize + 1)
        end
      end
    end
  end
end
