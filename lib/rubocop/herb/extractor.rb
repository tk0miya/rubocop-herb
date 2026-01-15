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
        path = processed_source.path
        return unless path && Configuration.supported_file?(path)

        source = Converter.new.convert(processed_source.raw_source)
        return unless source

        [{
          offset: 0,
          processed_source: build_processed_source(source)
        }]
      end

      private

      def build_processed_source(code) #: ::RuboCop::ProcessedSource
        ::RuboCop::ProcessedSource.new(
          code,
          processed_source.ruby_version,
          processed_source.path,
          parser_engine: processed_source.parser_engine
        ).tap do |ps|
          ps.config = processed_source.config
          ps.registry = processed_source.registry
        end
      end
    end
  end
end
