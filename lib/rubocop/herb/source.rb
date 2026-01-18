# frozen_string_literal: true

module RuboCop
  module Herb
    class Source
      include Characters

      attr_reader :code #: String
      attr_reader :line_offsets #: Array[Integer]

      # @rbs code: String
      def initialize(code) #: void
        @code = code
        @line_offsets = compute_line_offsets
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

      # Convert line and column (1-indexed line, 0-indexed column) to byte offset
      # @rbs line: Integer
      # @rbs column: Integer
      def byte_offset(line, column) #: Integer
        line_offsets[line - 1] + column
      end

      def compute_line_offsets #: Array[Integer]
        offsets = [0]
        code.bytes.each_with_index do |byte, index|
          offsets << (index + 1) if byte == LF
        end
        offsets
      end
    end
  end
end
