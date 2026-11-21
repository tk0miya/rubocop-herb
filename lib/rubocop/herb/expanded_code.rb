# frozen_string_literal: true

module RuboCop
  module Herb
    # The Ruby code to parse: the Ruby code rendered by RubyRenderer in which the markers of short texts are inserted.
    # A text of 1-2 characters has no room for the marker ("_a;") in the Ruby code keeping the positions of the source,
    # so it is replaced with the marker here, which shifts the code after it.
    # The positions in the result of parsing this code are converted back to the ones in the source
    # (see LocationRemapper), so that RuboCop gets an AST with the nodes of short texts at their positions.
    #
    #     source:    "<% if x %>a<% else %>b<% end %>"
    #     ruby_code: "   if x;       else;       end;  "
    #     code:      "   if x;  _a;     else;  _a;     end;  "
    class ExpandedCode
      # The marker of a short text, which is the same as the one of a text (see RubyRenderer)
      MARKER = "_a;" #: String

      # The offset of the semicolon in the marker
      SEMICOLON_OFFSET = MARKER.length - 1 #: Integer

      # A short text replaced with the marker
      Replacement = Data.define(
        :range,        #: CharRange -- the range of the short text in the source
        :expanded_pos  #: Integer -- the position of the marker in the expanded code
      )

      attr_reader :code #: String
      attr_reader :replacements #: Array[Replacement] -- sorted by position

      # @rbs ruby_code: String
      # @rbs short_text_ranges: Array[CharRange] -- the ranges of the short texts in the source
      def initialize(ruby_code, short_text_ranges) #: void
        @code = ruby_code.dup
        @replacements = []
        # Each replacement shifts the code after it by the difference of the lengths of the marker and the text
        shift = 0
        short_text_ranges.sort_by(&:from).each do |range|
          length = range.to - range.from
          replacements << Replacement.new(range:, expanded_pos: range.from + shift)
          code[range.from + shift, length] = MARKER
          shift += MARKER.length - length
        end
      end

      # Convert a position in the expanded code to the one in the source
      # The identifier of a marker (`_a`) is mapped to the short text, and its semicolon to the end of the text
      # @rbs pos: Integer
      def to_source_pos(pos) #: Integer
        replacement = preceding_replacement(pos)
        return pos unless replacement

        range = replacement.range
        offset = pos - replacement.expanded_pos
        if offset >= SEMICOLON_OFFSET
          # The semicolon has no character in the source, so it is mapped to the end of the text
          range.to + [offset - MARKER.length, 0].max.not_nil!
        else
          range.from + [offset, range.to - range.from].min.not_nil!
        end
      end

      # Whether the position in the expanded code is the semicolon of a marker
      # @rbs pos: Integer
      def marker_semicolon?(pos) #: bool
        replacement = preceding_replacement(pos)
        !replacement.nil? && pos - replacement.expanded_pos == SEMICOLON_OFFSET
      end

      private

      # The last replacement starting at the position or before it
      # @rbs pos: Integer
      def preceding_replacement(pos) #: Replacement?
        index = replacements.bsearch_index { _1.expanded_pos > pos } || replacements.size
        index.positive? ? replacements[index - 1] : nil
      end
    end
  end
end
