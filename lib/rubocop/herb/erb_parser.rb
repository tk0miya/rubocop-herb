# frozen_string_literal: true

require "herb"
require_relative "erb_parser/node_location_collector"
require_relative "erb_parser/tail_expression_collector"

module RuboCop
  module Herb
    # Parses ERB files and produces ParseResult objects.
    # Handles the parsing phase: calling Herb.parse, collecting ERB locations,
    # and computing line offsets.
    class ErbParser
      # Parse ERB code and return a ParseResult
      # @rbs path: String
      # @rbs code: String
      # @rbs html_visualization: bool
      def self.parse(path, code, html_visualization: false) #: ParseResult
        new.parse(path, code, html_visualization:)
      end

      # @rbs path: String
      # @rbs code: String
      # @rbs html_visualization: bool
      def parse(path, code, html_visualization: false) #: ParseResult
        source = Source.new(path:, code:)
        ast = ::Herb.parse(code)
        result = NodeLocationCollector.collect(source, ast, html_visualization:)
        tail_expressions = TailExpressionCollector.collect(ast, result.html_block_positions,
                                                           html_visualization:)

        ParseResult.new(
          source:,
          ast:,
          erb_locations: result.erb_locations,
          erb_max_columns: result.erb_max_columns,
          html_block_positions: result.html_block_positions,
          tail_expressions:,
          tags: result.tags
        )
      end
    end
  end
end
