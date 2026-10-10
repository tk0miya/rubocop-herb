# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Herb
    # Collects the lines where Layout/CommentIndentation should be disabled.
    # The cop compares the column of a comment with the code on the next non-blank line,
    # but a comment and the code written in different ERB tags (e.g. `<%# note %>` followed by `<%= x %>`)
    # are indented by the HTML structure. Such comments are found from the comments and the ERB tags
    # in the original source, so that comments followed by the code in the same ERB tag are still checked.
    class CommentIndentationCollector
      COP_NAME = "Layout/CommentIndentation" #: String

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
        lines = processed_source.comments.filter_map do |comment|
          line = comment.loc.line
          next unless own_line_comment?(line)

          next_code_pos = next_code_position(line)
          comment_tag = erb_tag_range(comment.source_range.begin_pos)
          next if comment_tag && next_code_pos && erb_tag_range(next_code_pos) == comment_tag

          line..line
        end
        lines.empty? ? {} : { COP_NAME => lines.uniq }
      end

      private

      # The cop checks only the comments written on their own lines
      # @rbs line: Integer -- 1-based line number
      def own_line_comment?(line) #: bool
        processed_source.lines[line - 1].to_s.match?(/\A\s*#/)
      end

      # The position of the first non-whitespace character on the next non-blank line of the line,
      # which is the code the cop compares the comment with
      # @rbs line: Integer -- 1-based line number
      def next_code_position(line) #: Integer?
        lines = processed_source.lines
        index = (line...lines.size).find { !lines[_1].to_s.strip.empty? }
        return unless index

        processed_source.buffer.line_range(index + 1).begin_pos + lines[index].to_s.index(/\S/).to_i
      end

      # The range of the ERB tag containing the position (nil for HTML)
      # @rbs pos: Integer
      def erb_tag_range(pos) #: CharRange?
        range = erb_tag_ranges.bsearch { _1.to > pos }
        range if range && range.from <= pos
      end
    end
  end
end
