# frozen_string_literal: true

module RuboCop
  module Herb
    class Converter
      attr_reader :html_visualization #: bool

      # @rbs html_visualization: bool
      def initialize(html_visualization: false) #: void
        @html_visualization = html_visualization
      end

      # @rbs code: String
      # @rbs path: String?
      def convert(code, path = nil) #: RubyRenderer::Result
        source = Source.new(code, path)
        RubyRenderer.render(source, html_visualization:)
      end
    end
  end
end
