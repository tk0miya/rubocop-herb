# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    class Converter
      attr_reader :html_visualization #: bool

      # @rbs html_visualization: bool
      def initialize(html_visualization: false) #: void
        @html_visualization = html_visualization
      end

      # @rbs code: String
      def convert(code) #: String?
        source = Source.new(code)
        parse_result = ::Herb.parse(code)

        # Continue processing even with HTML errors - ERB nodes may still be extractable
        RubyRenderer.render(source, parse_result, html_visualization: html_visualization)
      end
    end
  end
end
