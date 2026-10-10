# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Herb
    # Collects the lines where Style/Semicolon should be disabled.
    # Semicolons are rendered to terminate the code of ERB tags (e.g. `<%= x %>` becomes `_ = x;`)
    # and HTML visualized as Ruby code (e.g. `div;`), and the cop reports them.
    # Such semicolons are found from the tokens and the original source, so that semicolons
    # written in ERB tags are still checked unless a rendered semicolon is on the same line.
    class SemicolonCollector
      COP_NAME = "Style/Semicolon" #: String

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
        lines = processed_source.tokens.filter_map do |token|
          next unless token.semicolon?
          next if written_in_erb_tag?(token.begin_pos)

          token.line..token.line
        end
        lines.empty? ? {} : { COP_NAME => lines.uniq }
      end

      private

      # Check if the semicolon at the position is written in an ERB tag of the original source
      # @rbs pos: Integer
      def written_in_erb_tag?(pos) #: bool
        return false unless code[pos] == ";"

        range = erb_tag_ranges.bsearch { _1.to > pos }
        !range.nil? && range.from <= pos
      end
    end
  end
end
