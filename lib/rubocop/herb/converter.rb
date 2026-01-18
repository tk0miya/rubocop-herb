# frozen_string_literal: true

module RuboCop
  module Herb
    class Converter
      attr_reader :html_visualization #: bool

      # @rbs html_visualization: bool
      def initialize(html_visualization: false) #: void
        @html_visualization = html_visualization
      end

      # @rbs path: String
      # @rbs code: String
      def convert(path, code) #: RubyRenderer::Result
        source = Source.new(path, code)
        RubyRenderer.render(source, html_visualization:)
      end
    end
  end
end
