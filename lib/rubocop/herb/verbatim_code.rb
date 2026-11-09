# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Herb
    # Checks whether a range of the Ruby code is the code written in an ERB tag, copied verbatim from the ERB source.
    #
    # The conversion renders code which is not written in the ERB source: HTML as identifiers and whitespace
    # (e.g. `<div>` becomes `div;`), the delimiters of ERB tags as whitespace and markers (e.g. `<%= x %>` becomes
    # `_ = x;  `) and semicolons at the closing of ERB tags. A range covering such code covers characters other than
    # the code in an ERB tag, or characters differing from the ERB source.
    class VerbatimCode
      attr_reader :source #: Source
      attr_reader :code_ranges #: Array[CharRange] -- character ranges of the code in ERB tags sorted by position

      # @rbs parse_result: ParseResult
      def initialize(parse_result) #: void
        @source = parse_result.source
        @code_ranges = parse_result.erb_locations.values.filter_map do |loc|
          node = loc.node #: erb_node
          content = node.content
          NodeRange.byte_range_to_char_range(content.range, source) if content
        end.sort_by(&:from)
      end

      # Check if the range is in the code of a single ERB tag (excluding the delimiters)
      # and its characters are the same as the ERB source
      # @rbs range: ::Parser::Source::Range
      def include?(range) #: bool
        !code_range_of(range).nil?
      end

      # The range of the code of the ERB tag containing the range, if the range is verbatim code (see include?)
      # @rbs range: ::Parser::Source::Range
      def code_range_of(range) #: CharRange?
        code_range = code_ranges.bsearch { _1.to >= range.end_pos }
        return unless code_range && code_range.from <= range.begin_pos
        return unless source.slice(CharRange.new(range.begin_pos, range.end_pos)) == range.source

        code_range
      end
    end
  end
end
