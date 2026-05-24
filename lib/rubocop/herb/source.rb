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
      attr_reader :line_byte_offsets #: Array[Integer]
      attr_reader :line_char_offsets #: Array[Integer]

      # @rbs path: String
      # @rbs code: String
      def initialize(path:, code:) #: void
        @path = path
        @code = code
        @line_byte_offsets, @line_char_offsets = compute_line_offsets(code)
      end

      # Get the encoding of the source code
      def encoding #: Encoding
        code.encoding
      end

      # Get a substring by byte range
      # @rbs range: ::Herb::Range
      def byteslice(range) #: String
        sliced = code.byteslice(range.from, range.to - range.from).not_nil!
        sliced.force_encoding(code.encoding)
      end

      # Get a substring by character range
      # @rbs range: CharRange
      def slice(range) #: String
        code[range.from...range.to].not_nil!
      end

      # Convert byte position to character position
      # This is needed for converting Herb's byte-based positions to character-based positions
      # Uses binary search to find the line, then only processes bytes within that line
      # @rbs byte_pos: Integer
      def byte_to_char_pos(byte_pos) #: Integer
        # Binary search to find the line containing byte_pos
        line_idx = line_byte_offsets.bsearch_index { _1 > byte_pos } || line_byte_offsets.size
        line_idx -= 1 if line_idx.positive?

        # Get the starting positions for this line
        line_byte_start = line_byte_offsets.fetch(line_idx)
        line_char_start = line_char_offsets.fetch(line_idx)

        # Only process bytes within this line
        bytes_in_line = byte_pos - line_byte_start
        chars_in_line = code.byteslice(line_byte_start, bytes_in_line).not_nil!.length

        line_char_start + chars_in_line
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
        line_start = line_byte_offsets.fetch(line - 1)
        next_line_start = line_byte_offsets[line] || code.bytesize
        line_content = code.byteslice(line_start, next_line_start - line_start).not_nil!
        line_start + line_content.chars[0, column].not_nil!.join.bytesize
      end

      # Compute line offsets (both byte and character) for the source code
      # @rbs code: String
      def compute_line_offsets(code) #: [Array[Integer], Array[Integer]]
        byte_offsets = [0]
        char_offsets = [0]
        byte_total = 0
        char_total = 0

        code.each_line do |line|
          byte_total += line.bytesize
          char_total += line.length
          byte_offsets << byte_total
          char_offsets << char_total
        end

        [byte_offsets, char_offsets]
      end
    end
  end
end
