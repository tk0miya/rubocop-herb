# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    # Encapsulates source code and line offset information,
    # and converts between byte and character positions.
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
        from = char_to_byte_pos(range.from)
        code.byteslice(from, char_to_byte_pos(range.to) - from).not_nil!
      end

      # Convert byte position to character position
      # This is needed for converting Herb's byte-based positions to character-based positions
      # Uses binary search to find the line, then only processes bytes within that line
      # @rbs byte_pos: Integer
      def byte_to_char_pos(byte_pos) #: Integer
        line_idx = line_index(line_byte_offsets, byte_pos)

        # Get the starting positions for this line
        line_byte_start = line_byte_offsets.fetch(line_idx)
        line_char_start = line_char_offsets.fetch(line_idx)

        # Only process bytes within this line
        bytes_in_line = byte_pos - line_byte_start
        chars_in_line = code.byteslice(line_byte_start, bytes_in_line).not_nil!.length

        line_char_start + chars_in_line
      end

      # Convert character position to byte position
      # Indexing a string by characters takes linear time if it contains multi-byte characters,
      # so it finds the line with binary search, then only processes characters within that line
      # @rbs char_pos: Integer
      def char_to_byte_pos(char_pos) #: Integer
        return char_pos if code.ascii_only?

        line_idx = line_index(line_char_offsets, char_pos)

        # Only process characters within this line
        chars_in_line = char_pos - line_char_offsets.fetch(line_idx)
        bytes_in_line = line_at(line_idx)[0, chars_in_line].not_nil!.bytesize

        line_byte_offsets.fetch(line_idx) + bytes_in_line
      end

      # Convert a line and a column of Herb::Location to a character position
      # @rbs line: Integer -- 1-indexed line number
      # @rbs column: Integer -- 0-indexed character-based column
      def char_pos(line, column) #: Integer
        line_char_offsets.fetch(line - 1) + column
      end

      private

      # Binary search to find the index of the line containing the position
      # @rbs offsets: Array[Integer] -- line_byte_offsets or line_char_offsets
      # @rbs pos: Integer -- byte or character position (the same unit as offsets)
      def line_index(offsets, pos) #: Integer
        line_idx = offsets.bsearch_index { _1 > pos } || offsets.size
        line_idx.positive? ? line_idx - 1 : line_idx
      end

      # Get the line at the index
      # @rbs line_idx: Integer
      def line_at(line_idx) #: String
        line_byte_start = line_byte_offsets.fetch(line_idx)
        line_byte_end = line_byte_offsets.fetch(line_idx + 1, code.bytesize)
        code.byteslice(line_byte_start, line_byte_end - line_byte_start).not_nil!
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
