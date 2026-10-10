# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Herb
    # Collects the lines where Layout/ExtraSpacing should be disabled.
    # ERB tag delimiters and HTML are rendered as whitespace (e.g. `<%= a %> <%= b %>` becomes
    # `_ = a;  _ = b;`), so the cop reports the spaces between tokens on the line.
    # Such spaces are found from the tokens and the original source: spaces written by users are
    # whitespace in the original source and in an ERB tag. The spaces written in ERB tags are still
    # checked unless rendered spaces are on the same line.
    class ExtraSpacingCollector
      COP_NAME = "Layout/ExtraSpacing" #: String

      # Collect the disabled lines from a processed source
      # @rbs processed_source: ::RuboCop::AST::ProcessedSource
      # @rbs parse_result: ParseResult
      def self.collect(processed_source, parse_result) #: Hash[String, Array[Range[Integer]]]
        new(processed_source, parse_result).collect
      end

      attr_reader :tokens #: Array[::RuboCop::AST::Token]
      attr_reader :code #: String
      attr_reader :erb_tag_ranges #: Array[CharRange]

      # @rbs processed_source: ::RuboCop::AST::ProcessedSource
      # @rbs parse_result: ParseResult
      def initialize(processed_source, parse_result) #: void
        # Spaces before newlines are trailing whitespace, which the cop does not check
        @tokens = processed_source.tokens.reject { _1.type == :tNL }
        @code = parse_result.code
        @erb_tag_ranges = parse_result.erb_tag_ranges
      end

      def collect #: Hash[String, Array[Range[Integer]]]
        lines = tokens.each_with_index.filter_map do |token, index|
          next_token = tokens[index + 1]
          token.line..token.line if next_token && rendered_spaces_between?(token, next_token)
        end
        lines.empty? ? {} : { COP_NAME => lines.uniq }
      end

      private

      # Check if the spaces between the tokens are reported by the cop and rendered by the conversion
      # @rbs token: ::RuboCop::AST::Token
      # @rbs next_token: ::RuboCop::AST::Token
      def rendered_spaces_between?(token, next_token) #: bool
        return false unless token.line == next_token.line
        # A single space is not reported by the cop
        return false if next_token.begin_pos - token.end_pos < 2

        !written_in_erb_tag?(token.end_pos, next_token.begin_pos)
      end

      # Check if the spaces in the range are written in an ERB tag of the original source
      # @rbs from: Integer
      # @rbs to: Integer
      def written_in_erb_tag?(from, to) #: bool
        return false unless code[from...to].to_s.match?(/\A\s*\z/)

        range = erb_tag_ranges.bsearch { _1.to > from }
        !range.nil? && range.from <= from && to <= range.to
      end
    end
  end
end
