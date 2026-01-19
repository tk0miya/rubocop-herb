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
        source = Source.new(path, code)
        render_result = RubyRenderer.render(source, html_visualization:)
        hybrid_code = generate_hybrid_code(render_result.code, source, render_result.tags)
        Result.new(ruby_code: render_result.code, hybrid_code:, tags: render_result.tags)
      end

      private

      # Generate hybrid code by restoring original HTML at tag positions
      # @rbs ruby_code: String
      # @rbs source: Source
      # @rbs tags: Hash[Integer, Tag]
      def generate_hybrid_code(ruby_code, source, tags) #: String
        return ruby_code if tags.empty?

        result = ruby_code.bytes.dup
        tags.each do |position, tag|
          original_html_bytes = source.byteslice(tag.range).bytes
          result[position, original_html_bytes.length] = original_html_bytes
        end
        result.pack("C*").force_encoding(ruby_code.encoding)
      end
    end
  end
end
