# frozen_string_literal: true

module RuboCop
  module Herb
    # The marker of HTML (a tag, text, a comment and so on): a Ruby identifier standing for the HTML in the AST,
    # so that the cops see where HTML is (e.g. `div` for `<div>` and `_a` for text).
    # The markers are not rendered in the Ruby code keeping the positions of the source, as the HTML may have
    # no room for them (e.g. text of 1 character). They are inserted into the code to parse instead (see ExpandedCode).
    HtmlMarker = Data.define(
      :range,  #: CharRange -- the range of the HTML in the source, which the node of the marker gets
      :name    #: String -- the identifier
    )

    # Methods are defined by reopening the class (not in a Data.define block)
    # so that rbs-inline can generate their type signatures.
    class HtmlMarker
      # The Ruby code to parse: the identifier terminated by a semicolon,
      # as the code following the HTML may be on the same line (e.g. `a<%= x %>` becomes `_a;_ = x;`)
      def code #: String
        "#{name};"
      end

      # The start of the range in the source
      def from #: Integer
        range.from
      end

      # The end of the range in the source
      def to #: Integer
        range.to
      end

      # The length of the range in the source
      def length #: Integer
        range.to - range.from
      end
    end
  end
end
