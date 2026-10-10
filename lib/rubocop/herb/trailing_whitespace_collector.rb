# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Herb
    # Collects the lines where Layout/TrailingWhitespace should be disabled.
    # ERB tag delimiters and HTML at the end of lines are rendered as whitespace
    # (e.g. `<%= x %>` becomes `_ = x;  `), so the cop reports them as trailing whitespace.
    # Such whitespace is found from the lines and the original source: trailing whitespace written by users
    # is whitespace in the original source and in an ERB tag (e.g. a line in a multi-line ERB tag).
    class TrailingWhitespaceCollector
      COP_NAME = "Layout/TrailingWhitespace" #: String

      # Collect the disabled lines from a processed source
      # @rbs processed_source: ::RuboCop::AST::ProcessedSource
      # @rbs parse_result: ParseResult
      def self.collect(processed_source, parse_result) #: Hash[String, Array[Range[Integer]]]
        new(processed_source, parse_result).collect
      end

      attr_reader :processed_source #: ::RuboCop::AST::ProcessedSource
      attr_reader :code #: String
      attr_reader :erb_tag_ranges #: Array[CharRange]

      # @rbs processed_source: ::RuboCop::AST::ProcessedSource
      # @rbs parse_result: ParseResult
      def initialize(processed_source, parse_result) #: void
        @processed_source = processed_source
        @code = parse_result.code
        @erb_tag_ranges = parse_result.erb_tag_ranges
      end

      def collect #: Hash[String, Array[Range[Integer]]]
        lines = processed_source.lines.each_with_index.filter_map do |line, index|
          lineno = index + 1
          lineno..lineno if rendered_trailing_whitespace?(line, lineno)
        end
        lines.empty? ? {} : { COP_NAME => lines }
      end

      private

      # Check if the line has trailing whitespace rendered by the conversion
      # @rbs line: String
      # @rbs lineno: Integer
      def rendered_trailing_whitespace?(line, lineno) #: bool
        trailing_whitespace = line[/[[:blank:]]+\z/]
        return false unless trailing_whitespace

        to = processed_source.buffer.line_range(lineno).end_pos
        !written_in_erb_tag?(to - trailing_whitespace.length, to)
      end

      # Check if the whitespace in the range is written in an ERB tag of the original source
      # @rbs from: Integer
      # @rbs to: Integer
      def written_in_erb_tag?(from, to) #: bool
        return false unless code[from...to].to_s.match?(/\A[[:blank:]]*\z/)

        range = erb_tag_ranges.bsearch { _1.to > from }
        !range.nil? && range.from <= from && to <= range.to
      end
    end
  end
end
