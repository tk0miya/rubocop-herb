# frozen_string_literal: true

module RuboCop
  module Herb
    # The Ruby code to parse: the Ruby code rendered by RubyRenderer in which the markers of HTML are inserted.
    # The Ruby code keeps the positions of the source and has whitespace at HTML, so each range of HTML with a marker
    # is replaced with the code of the marker here, which shifts the code after it.
    # The positions in the result of parsing this code are converted back to the ones in the source
    # (see LocationRemapper), so that RuboCop gets an AST with the nodes of the markers at the HTML.
    #
    #     source:    "<p><% if x %>a<% else %>b<% end %></p>"
    #     ruby_code: "      if x;      else;      end;      "
    #     code:      "p;     if x;  _a;   else;  _a;   end;  p;   "
    class ExpandedCode
      # A range of HTML replaced with the code of its marker
      Replacement = Data.define(
        :marker,       #: HtmlMarker
        :expanded_pos  #: Integer -- the position of the code of the marker in the expanded code
      )

      attr_reader :code #: String
      attr_reader :replacements #: Array[Replacement] -- sorted by position

      # @rbs ruby_code: String
      # @rbs markers: Array[HtmlMarker] -- the ranges of the markers must not overlap
      def initialize(ruby_code, markers) #: void
        @code = ruby_code.dup
        @replacements = []
        # Each replacement shifts the code after it by the difference of the lengths of the marker and the HTML
        shift = 0
        markers.sort_by(&:from).each do |marker|
          replacements << Replacement.new(marker:, expanded_pos: marker.from + shift)
          code[marker.from + shift, marker.length] = marker.code
          shift += marker.code.length - marker.length
        end
      end

      # Convert a position in the expanded code to the one in the source
      # The identifier of a marker is mapped to its range in the source, and its semicolon to the end of the range
      # @rbs pos: Integer
      def to_source_pos(pos) #: Integer
        replacement = preceding_replacement(pos)
        return pos unless replacement

        marker = replacement.marker
        offset = pos - replacement.expanded_pos
        following = offset - marker.code.length
        # The semicolon has no character in the source, so it is mapped to the end of the range
        return marker.to + [following, 0].max.not_nil! if following >= -1

        marker.from + [offset, marker.length].min.not_nil!
      end

      # Whether the position in the expanded code is the semicolon of a marker
      # @rbs pos: Integer
      def marker_semicolon?(pos) #: bool
        replacement = preceding_replacement(pos)
        !replacement.nil? && pos - replacement.expanded_pos == replacement.marker.code.length - 1
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
