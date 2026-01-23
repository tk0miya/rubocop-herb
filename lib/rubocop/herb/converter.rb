# frozen_string_literal: true

module RuboCop
  module Herb
    class Converter
      # Result of converting ERB source
      Result = Data.define(
        :ruby_code, #: String
        :hybrid_code, #: String
        :tags #: Hash[Integer, Tag]
      )

      attr_reader :html_visualization #: bool

      # @rbs html_visualization: bool
      def initialize(html_visualization: false) #: void
        @html_visualization = html_visualization
      end

      # @rbs path: String
      # @rbs code: String
      def convert(path, code) #: Result
        parse_result = ErbParser.parse(path, code)
        render_result = RubyRenderer.render(parse_result, html_visualization:)
        hybrid_code = generate_hybrid_code(render_result.code, parse_result, render_result.tags)
        Result.new(ruby_code: render_result.code, hybrid_code:, tags: render_result.tags)
      end

      private

      # Generate hybrid code by restoring original HTML at tag positions
      # Only restores tags with restore_source: true
      # @rbs ruby_code: String
      # @rbs parse_result: ParseResult
      # @rbs tags: Hash[Integer, Tag]
      def generate_hybrid_code(ruby_code, parse_result, tags) #: String
        restorable_tags = tags.select { |_, tag| tag.restore_source }
        return ruby_code if restorable_tags.empty?

        result = ruby_code.bytes.dup
        restorable_tags.each do |position, tag|
          original_html_bytes = parse_result.byteslice(tag.range).bytes
          result[position, original_html_bytes.length] = original_html_bytes
        end
        result.pack("C*").force_encoding(ruby_code.encoding)
      end
    end
  end
end
