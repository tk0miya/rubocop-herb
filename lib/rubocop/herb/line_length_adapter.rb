# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Herb
    # Prepended to RuboCop::Cop::Layout::LineLength to break lines only at the semicolons written in ERB templates.
    # The cop prefers breaking a line after a semicolon to breaking it in an expression (e.g. between arguments),
    # but the conversion renders semicolons at the closing delimiters of ERB tags (`<%= x %>` becomes `_ = x;  `),
    # so the cop would move `%>` to the next line instead of shortening the line.
    # The corrections breaking lines outside the code of ERB tags are rejected by CopCorrectionGuard.
    module LineLengthAdapter
      # @rbs!
      #   def processed_source: () -> ::RuboCop::AST::ProcessedSource?
      #   def breakable_range_by_line_index: () -> Hash[Integer, ::Parser::Source::Range]
      #   def breakable_range_after_semicolon: (::RuboCop::AST::Token) -> ::Parser::Source::Range?

      private

      # @rbs source: ::RuboCop::AST::ProcessedSource
      def check_for_breakable_semicolons(source) #: void
        return super unless source.is_a?(ProcessedSource)

        parse_result = source.parse_result
        semicolons = source.tokens.select { _1.type == :tSEMI && written_semicolon?(parse_result, _1.begin_pos) }
        semicolons.reverse_each do |token|
          range = breakable_range_after_semicolon(token)
          breakable_range_by_line_index[range.line - 1] = range if range
        end
      end

      # Whether the semicolon at the position is written in an ERB tag
      # The semicolons rendered from HTML text (e.g. `_a;` for `ab; text`) may land on a semicolon in the text,
      # so the position must be in an ERB tag
      # @rbs parse_result: ParseResult
      # @rbs pos: Integer
      def written_semicolon?(parse_result, pos) #: bool
        tag = parse_result.erb_tag_ranges.bsearch { _1.to > pos }
        return false unless tag && tag.from <= pos

        parse_result.slice(CharRange.new(pos, pos + 1)) == ";"
      end
    end
  end
end

RuboCop::Cop::Layout::LineLength.prepend(RuboCop::Herb::LineLengthAdapter)
