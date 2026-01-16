# frozen_string_literal: true

module RuboCop
  module Herb
    class Source
      attr_reader :code #: String

      # @rbs code: String
      def initialize(code) #: void
        @code = code
      end

      # @rbs range: ::Herb::Range
      def byteslice(range) #: String
        code.byteslice(range.from, range.to - range.from).force_encoding(code.encoding)
      end

      def encoding #: Encoding
        code.encoding
      end
    end
  end
end
