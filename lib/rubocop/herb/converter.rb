# frozen_string_literal: true

module RuboCop
  module Herb
    class Converter
      # Result of converting ERB source
      Result = Data.define(
        :ruby_code, #: String
        :hybrid_code, #: String
        :parse_result #: ParseResult
      )

      attr_reader :html_visualization #: bool

      # @rbs html_visualization: bool
      def initialize(html_visualization: false) #: void
        @html_visualization = html_visualization
      end

      # @rbs path: String
      # @rbs code: String
      def convert(path, code) #: Result
        parse_result = ErbParser.parse(path, code, html_visualization:)
        ruby_code = RubyRenderer.render(parse_result, html_visualization:)
        hybrid_code = generate_hybrid_code(ruby_code, parse_result)
        Result.new(ruby_code:, hybrid_code:, parse_result:)
      end

      private

      # Generate hybrid code by restoring original HTML at tag positions
      # Only restores tags with restore_source: true
      # @rbs ruby_code: String
      # @rbs parse_result: ParseResult
      def generate_hybrid_code(ruby_code, parse_result) #: String
        restorable_tags = parse_result.tags.select { |_, tag| tag.restore_source }
        return ruby_code if restorable_tags.empty?

        result = ruby_code.chars
        restorable_tags.each_value do |tag|
          original_html = parse_result.slice(tag.char_from, tag.char_to)
          result[tag.char_from, original_html.length] = original_html.chars
        end
        result.join
      end
    end
  end
end
