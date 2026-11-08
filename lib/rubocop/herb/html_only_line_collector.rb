# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Herb
    # Collects the lines without ERB tags (HTML only and blank lines), where Layout/LineLength should be disabled,
    # as RuboCop checks the Ruby code in ERB tags only.
    # The length of HTML lines is left to the formatter of Herb (herb-format) as it wraps HTML
    # (e.g. attributes) by its own limit.
    # Lines with ERB tags (including the lines of a multi-line ERB tag) are still checked,
    # as herb-format does not wrap the Ruby code in ERB tags.
    # The cop reports the part of a line over the limit, which may be HTML on a line with ERB tags,
    # so it is disabled by lines, not by VerbatimCode.
    class HtmlOnlyLineCollector
      COP_NAME = "Layout/LineLength" #: String

      # Collect the disabled lines from a processed source
      # @rbs processed_source: ::RuboCop::AST::ProcessedSource
      # @rbs parse_result: ParseResult
      def self.collect(processed_source, parse_result) #: Hash[String, Array[Range[Integer]]]
        new(processed_source, parse_result).collect
      end

      attr_reader :processed_source #: ::RuboCop::AST::ProcessedSource
      attr_reader :erb_tag_ranges #: Array[CharRange]

      # @rbs processed_source: ::RuboCop::AST::ProcessedSource
      # @rbs parse_result: ParseResult
      def initialize(processed_source, parse_result) #: void
        @processed_source = processed_source
        @erb_tag_ranges = parse_result.erb_tag_ranges
      end

      def collect #: Hash[String, Array[Range[Integer]]]
        # Unlike ProcessedSource#lines, String#lines does not count the empty line after the last newline
        line_count = processed_source.raw_source.lines.size
        lines = (1..line_count).filter_map { _1.._1 unless erb_tag_at_line?(_1) }
        lines.empty? ? {} : { COP_NAME => lines }
      end

      private

      # Check if an ERB tag (or a part of a multi-line one) is at the line
      # @rbs lineno: Integer
      def erb_tag_at_line?(lineno) #: bool
        line_range = processed_source.buffer.line_range(lineno)
        range = erb_tag_ranges.bsearch { _1.to > line_range.begin_pos }
        !range.nil? && range.from < line_range.end_pos
      end
    end
  end
end
