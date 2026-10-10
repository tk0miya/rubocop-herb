# frozen_string_literal: true

module RuboCop
  module Herb
    class Extractor
      class << self
        # @rbs processed_source: ::RuboCop::ProcessedSource
        def call(processed_source) #: ::RuboCop::Runner::extractorResult
          new(processed_source).call
        end
      end

      attr_reader :processed_source #: ::RuboCop::ProcessedSource

      # @rbs processed_source: ::RuboCop::ProcessedSource
      def initialize(processed_source) #: void
        @processed_source = processed_source
      end

      def call #: RuboCop::Runner::extractorResult
        path = processed_source.path
        return unless path && Configuration.supported_file?(path)

        # Convert the source normalized by Parser::Source::Buffer (CRLF to LF) so that
        # the positions in the result match the buffer of the original processed source
        result = Converter.new(html_visualization: Configuration.html_visualization?)
                          .convert(path, processed_source.buffer.source)

        [{
          offset: 0,
          processed_source: build_processed_source(result)
        }]
      end

      private

      # @rbs result: Converter::Result
      def build_processed_source(result) #: ProcessedSource
        ProcessedSource.new(
          restore_crlf(result.ruby_code),
          processed_source.ruby_version,
          processed_source.path,
          hybrid_code: result.hybrid_code,
          parse_result: result.parse_result,
          parser_engine: processed_source.parser_engine
        ).tap do |ps|
          ps.config = processed_source.config
          ps.registry = processed_source.registry
        end
      end

      # Restore CRLF line endings of the raw source so that cops checking the raw source
      # (e.g. Layout/EndOfLine) still work. The conversion keeps lines as is,
      # so the lines of the Ruby code correspond to those of the raw source.
      # @rbs ruby_code: String
      def restore_crlf(ruby_code) #: String
        raw_source = processed_source.raw_source
        return ruby_code unless raw_source.include?("\r\n")

        raw_lines = raw_source.lines
        ruby_code.lines.each_with_index.map do |line, index|
          raw_lines[index]&.end_with?("\r\n") ? line.sub(/\n\z/, "\r\n") : line
        end.join
      end
    end
  end
end
