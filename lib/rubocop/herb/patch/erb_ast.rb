# frozen_string_literal: true

require "rubocop/ast"
require "parser/source/range"

module RuboCop
  module Herb
    module Patch
      # Monkey patches for AST classes to handle ERB tag ranges
      # When ERB tag ranges (keyword, else, end) are adjusted to include
      # the full ERB tags (e.g., "<% if %>" instead of just "if"),
      # methods like if?, is?, etc. need to extract the actual Ruby keyword.
      module ErbAst
        KEYWORD_PATTERN = /\A(?:<%=?)?\s*(?<keyword>\w+)/ #: Regexp

        # Patches for RuboCop::AST::IfNode
        module IfNodePatch
          # Override keyword to extract actual keyword from ERB tag
          def keyword #: String
            return "" if ternary?

            loc.keyword.source[KEYWORD_PATTERN, :keyword] || ""
          end
        end

        # Patches for Parser::Source::Range
        module RangePatch
          # Override is? to handle ERB-wrapped content
          # @rbs what: Array[String]
          def is?(*what) #: bool
            keyword = source[KEYWORD_PATTERN, :keyword]
            what.include?(keyword) || what.include?(source)
          end
        end

        # Apply patches when module is loaded
        RuboCop::AST::IfNode.prepend(IfNodePatch)
        Parser::Source::Range.prepend(RangePatch)
      end
    end
  end
end
