# frozen_string_literal: true

module RuboCop
  module Herb
    class Source
      attr_reader :code #: String

      # @rbs code: String
      def initialize(code) #: void
        @code = code
      end

      def lines #: Array[String]
        @lines ||= code.lines
      end

      def offsets #: Array[Integer]
        @offsets ||= lines.inject([0]) { |acc, line| acc << (acc.last + line.size) }
      end

      def byte_offsets #: Array[Integer]
        @byte_offsets ||= lines.inject([0]) { |acc, line| acc << (acc.last + line.bytesize) }
      end

      # @rbs start_line: Integer
      # @rbs start_column: Integer -- byte offset within the line
      # @rbs end_line: Integer
      # @rbs end_column: Integer -- byte offset within the line
      def slice(start_line, start_column, end_line, end_column) #: String
        from = byte_offsets[start_line - 1] + start_column
        to = byte_offsets[end_line - 1] + end_column
        code.byteslice(from, to - from).force_encoding(code.encoding)
      end

      # @rbs start_line: Integer
      # @rbs start_column: Integer -- byte offset within the line
      # @rbs end_line: Integer
      # @rbs end_column: Integer -- byte offset within the line
      def byte_range(start_line, start_column, end_line, end_column) #: [Integer, Integer]
        from = byte_offsets[start_line - 1] + start_column
        to = byte_offsets[end_line - 1] + end_column
        [from, to]
      end

      def encoding #: Encoding
        code.encoding
      end
    end
  end
end
