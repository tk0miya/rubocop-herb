# frozen_string_literal: true

module RuboCop
  module Herb
    class Extractor
      class << self
        # @rbs processed_source: ::RuboCop::ProcessedSource
        def call(processed_source) #: extractorResult
          new(processed_source).call
        end
      end

      attr_reader :processed_source #: ::RuboCop::ProcessedSource

      # @rbs processed_source: ::RuboCop::ProcessedSource
      def initialize(processed_source) #: void
        @processed_source = processed_source
      end

      def call #: extractorResult
        nil
      end
    end
  end
end
