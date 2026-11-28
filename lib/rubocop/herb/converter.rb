# frozen_string_literal: true

module RuboCop
  module Herb
    # Converts an ERB source to Ruby code keeping the positions of the source:
    # parses it with ErbParser and renders the Ruby code with RubyRenderer
    # The Ruby code has only the code in ERB tags; HTML is returned as markers (see HtmlMarker)
    class Converter
      # Result of converting ERB source
      Result = Data.define(
        :ruby_code,     #: String
        :parse_result,  #: ParseResult
        :html_markers   #: Array[HtmlMarker]
      )

      # @rbs path: String
      # @rbs code: String
      def convert(path, code) #: Result
        parse_result = ErbParser.parse(path, code)
        renderer = RubyRenderer.render(parse_result)
        Result.new(ruby_code: renderer.ruby_code, parse_result:, html_markers: renderer.html_markers)
      end
    end
  end
end
