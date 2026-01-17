# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    class Converter
      # @rbs code: String
      def convert(code) #: String?
        source = Source.new(code)
        parse_result = ::Herb.parse(code)

        # Continue processing even with HTML errors - ERB nodes may still be extractable
        RubyRenderer.render(source, parse_result)
      end
    end
  end
end
