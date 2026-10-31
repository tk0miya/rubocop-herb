# frozen_string_literal: true

module RuboCop
  module Herb
    class Converter
      # Result of converting ERB source
      Result = Data.define(
        :ruby_code,    #: String
        :parse_result  #: ParseResult
      )

      # @rbs path: String
      # @rbs code: String
      def convert(path, code) #: Result
        parse_result = ErbParser.parse(path, code)
        ruby_code = RubyRenderer.render(parse_result)
        Result.new(ruby_code:, parse_result:)
      end
    end
  end
end
