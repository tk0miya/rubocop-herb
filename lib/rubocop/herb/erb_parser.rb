# frozen_string_literal: true

require "herb"
require_relative "erb_parser/erb_location_collector"

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
        result = ErbLocationCollector.collect(ast)
        line_offsets = compute_line_offsets(code)

        ParseResult.new(
          path:,
          code:,
          ast:,
          erb_locations: result.locations,
          erb_max_columns: result.erb_max_columns,
          line_offsets:
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
