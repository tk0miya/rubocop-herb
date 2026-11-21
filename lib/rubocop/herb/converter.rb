# frozen_string_literal: true

module RuboCop
  module Herb
    # Converts an ERB source to Ruby code keeping the positions of the source:
    # parses it with ErbParser and renders the Ruby code with RubyRenderer
    # The texts too short to be rendered in the Ruby code are returned as ranges (see ExpandedCode)
    class Converter
      # Result of converting ERB source
      Result = Data.define(
        :ruby_code,         #: String
        :parse_result,      #: ParseResult
        :short_text_ranges  #: Array[CharRange] -- the texts too short to be rendered in the Ruby code
      )

      # @rbs path: String
      # @rbs code: String
      def convert(path, code) #: Result
        parse_result = ErbParser.parse(path, code)
        renderer = RubyRenderer.render(parse_result)
        Result.new(ruby_code: renderer.ruby_code, parse_result:, short_text_ranges: renderer.short_text_ranges)
      end
    end
  end
end
