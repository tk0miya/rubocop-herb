# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    class Converter
      attr_reader :source #: Source
      attr_reader :parse_result #: ::Herb::ParseResult

      LF = 0x0A
      CR = 0x0D
      SPACE = 0x20

      # @rbs source: String
      def convert(source) #: String?
        @source = Source.new(source)
        @parse_result = ::Herb.parse(source)

        # Continue processing even with HTML errors - ERB nodes may still be extractable
        build_ruby_code
      end

      private

      def build_ruby_code #: String
        erb_nodes = ErbNodeCollector.collect(parse_result)

        buffer = bleach_code(source.code)
        ErbNodeRenderer.render(buffer, source, erb_nodes)

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
    end
  end
end
