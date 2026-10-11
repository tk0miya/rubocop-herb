# frozen_string_literal: true

module RuboCop
  module Herb
    class Converter
      # Result of converting ERB source
      Result = Data.define(
        :ruby_code,    #: String
        :hybrid_code,  #: String
        :parse_result  #: ParseResult
      )

      # @rbs path: String
      # @rbs code: String
      def convert(path, code) #: Result
        parse_result = ErbParser.parse(path, code)
        ruby_code = RubyRenderer.render(parse_result)
        hybrid_code = generate_hybrid_code(ruby_code, parse_result)
        Result.new(ruby_code:, hybrid_code:, parse_result:)
      end

      private

      # Generate hybrid code by restoring original HTML at tag positions
      # Only restores tags with restore_source: true
      # @rbs ruby_code: String
      # @rbs parse_result: ParseResult
      def generate_hybrid_code(ruby_code, parse_result) #: String
        ranges = restorable_ranges(parse_result)
        return ruby_code if ranges.empty?

        # Concatenate the Ruby code and the original HTML of the tags from the beginning
        ruby_source = Source.new(path: parse_result.source.path, code: ruby_code)
        hybrid_code = +""
        pos = 0
        ranges.each do |range|
          hybrid_code << ruby_source.slice(CharRange.new(pos, range.from)) << parse_result.slice(range)
          pos = range.to
        end
        hybrid_code << ruby_source.slice(CharRange.new(pos, ruby_code.length))
      end

      # Character ranges of the tags with restore_source: true in ascending order
      # Tags can be nested (e.g. an element restored as a whole contains its child elements and text),
      # so only the outermost ones are returned
      # @rbs parse_result: ParseResult
      def restorable_ranges(parse_result) #: Array[CharRange]
        ranges = parse_result.tags.values.select(&:restore_source).map(&:range)
        ranges.sort_by { [_1.from, -_1.to] }.each_with_object([]) do |range, outermost|
          last = outermost.last
          outermost << range unless last && range.from < last.to
        end
      end
    end
  end
end
