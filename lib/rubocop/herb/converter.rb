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
        restorable_tags = parse_result.tags.select { |_, tag| tag.restore_source }
        return ruby_code if restorable_tags.empty?

        hybrid_code = ruby_code.dup
        restorable_tags.each do |char_pos, tag|
          original_html = parse_result.slice(tag.range)
          hybrid_code[char_pos, original_html.length] = original_html
        end
        hybrid_code
      end
    end
  end
end
