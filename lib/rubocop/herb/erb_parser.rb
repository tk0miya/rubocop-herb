# frozen_string_literal: true

require "herb"
require_relative "erb_parser/erb_location_collector"
require_relative "erb_parser/html_block_collector"

module RuboCop
  module Herb
    # Parses ERB files and produces ParseResult objects.
    # Handles the parsing phase: calling Herb.parse, collecting ERB locations,
    # and computing line offsets.
    class ErbParser
      # Parse ERB code and return a ParseResult
      # @rbs path: String
      # @rbs code: String
      def self.parse(path, code) #: ParseResult
        new.parse(path, code)
      end

      # @rbs path: String
      # @rbs code: String
      def parse(path, code) #: ParseResult
        ast = ::Herb.parse(code)
        erb_result = ErbLocationCollector.collect(ast)
        html_block_positions = HtmlBlockCollector.collect(ast, erb_result.locations)
        line_offsets = compute_line_offsets(code)

        ParseResult.new(
          path:,
          code:,
          ast:,
          erb_locations: erb_result.locations,
          erb_max_columns: erb_result.erb_max_columns,
          line_offsets:,
          html_block_positions:
        )
      end

      private

      # @rbs code: String
      def compute_line_offsets(code) #: Array[Integer]
        code.split("\n", -1)[0...-1].inject([0]) do |offsets, line|
          offsets << (offsets.last + line.bytesize + 1)
        end
      end
    end
  end
end
