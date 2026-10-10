# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Herb
    # Collects the lines where Layout/IndentationConsistency should be disabled.
    # The cop compares the column of each statement in a body with the first statement of the body,
    # but statements written in different ERB tags (and HTML rendered with html_visualization) are
    # indented by the HTML structure (e.g. `<% a = 1 %>` and `<p><% b = 2 %></p>` on the next lines).
    # Such statements are found from the Ruby AST and the ERB tags in the original source,
    # so that statements written in the same ERB tag as the first statement are still checked.
    class IndentationConsistencyCollector
      COP_NAME = "Layout/IndentationConsistency" #: String

      # Collect the disabled lines from a processed source
      # @rbs processed_source: ::RuboCop::AST::ProcessedSource
      # @rbs parse_result: ParseResult
      def self.collect(processed_source, parse_result) #: Hash[String, Array[Range[Integer]]]
        new(processed_source, parse_result).collect
      end

      attr_reader :ast #: ::RuboCop::AST::Node?
      attr_reader :erb_tag_ranges #: Array[CharRange]

      # @rbs processed_source: ::RuboCop::AST::ProcessedSource
      # @rbs parse_result: ParseResult
      def initialize(processed_source, parse_result) #: void
        @ast = processed_source.ast
        @erb_tag_ranges = parse_result.erb_tag_ranges
      end

      # The cop reports a statement at its first line, so only the first line of each statement is disabled
      def collect #: Hash[String, Array[Range[Integer]]]
        lines = [] #: Array[Range[Integer]]
        ast&.each_node(:begin, :kwbegin) do |node|
          first, *rest = node.children #: Array[::RuboCop::AST::Node]
          next unless first

          first_tag = erb_tag_range(first)
          rest.each do |statement|
            next if first_tag && erb_tag_range(statement) == first_tag

            lines << (statement.first_line..statement.first_line)
          end
        end
        lines.empty? ? {} : { COP_NAME => lines.uniq }
      end

      private

      # The range of the ERB tag containing the start of the node (nil for HTML rendered with html_visualization)
      # @rbs node: ::RuboCop::AST::Node
      def erb_tag_range(node) #: CharRange?
        pos = node.source_range.begin_pos
        range = erb_tag_ranges.bsearch { _1.to > pos }
        range if range && range.from <= pos
      end
    end
  end
end
