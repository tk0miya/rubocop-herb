# frozen_string_literal: true

module RuboCop
  module Herb
    class Converter
      attr_reader :source #: String
      attr_reader :parse_result #: ::Herb::ParseResult

      LF = 0x0A
      CR = 0x0D
      SPACE = 0x20
      SEMICOLON = 0x3B

      # @rbs source: String
      def convert(source) #: String?
        @source = source
        @parse_result = ::Herb.parse(source)

        return nil if parse_result.errors.any?

        build_ruby_code
      end

      private

      def source_lines #: Array[String]
        @source_lines ||= source.lines
      end

      def source_offsets #: Array[Integer]
        @source_offsets ||= source_lines.inject([0]) { |offsets, line| offsets << (offsets.last + line.size) }
      end

      def byte_offsets #: Array[Integer]
        @byte_offsets ||= source_lines.inject([0]) { |offsets, line| offsets << (offsets.last + line.bytesize) }
      end

      def build_ruby_code #: String
        collector = ErbNodeCollector.new
        parse_result.visit(collector)

        buffer = bleach_code(source)
        collector.nodes.each do |node|
          ruby_code = ruby_code_for(node)
          bytes = ruby_code.bytes
          from, to = byte_location_for(node)
          buffer[from, bytes.size] = bytes

          trailing_spaces = ruby_code.bytesize - ruby_code.rstrip.bytesize
          semicolon_pos = to - trailing_spaces
          buffer[semicolon_pos] = SEMICOLON if semicolon_pos < buffer.size
        end

        buffer.pack("C*").force_encoding(source.encoding)
      end

      # @rbs code: String
      def bleach_code(code) #: Array[Integer]
        code.bytes.map do |byte|
          case byte
          when LF, CR
            byte
          else
            SPACE
          end
        end
      end

      # @rbs node: ::Herb::AST::Node
      def ruby_code_for(node) #: String # rubocop:disable Metrics/AbcSize
        start = node.content.location.start
        end_ = node.content.location.end

        from = source_offsets[start.line - 1] + start.column
        to = source_offsets[end_.line - 1] + end_.column
        source[from...to]
      end

      def byte_location_for(node) #: [Integer, Integer] # rubocop:disable Metrics/AbcSize
        start = node.content.location.start
        end_ = node.content.location.end

        from = byte_offsets[start.line - 1] + source_lines[start.line - 1][0...start.column].bytesize
        to = byte_offsets[end_.line - 1] + source_lines[end_.line - 1][0...end_.column].bytesize

        [from, to]
      end
    end
  end
end
