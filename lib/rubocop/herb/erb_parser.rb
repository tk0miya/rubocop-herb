# frozen_string_literal: true

require "herb"
require_relative "erb_parser/disabled_cops_collector"
require_relative "erb_parser/node_location_collector"

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
        source = Source.new(path:, code:)
        # Herb treats a lone `\r` as a newline, but Ruby and RuboCop treat it as a space.
        # Replace it with a space (same size) so that the lines of Herb locations match the source.
        ast = ::Herb.parse(code.gsub(/\r(?!\n)/, " "))
        result = NodeLocationCollector.collect(source, ast)

        ParseResult.new(
          source:,
          ast:,
          erb_locations: result.erb_locations,
          erb_positions: result.erb_positions,
          erb_tag_ranges: result.erb_tag_ranges,
          tags: result.tags,
          disabled_cops: DisabledCopsCollector.collect(ast)
        )
      end
    end
  end
end
