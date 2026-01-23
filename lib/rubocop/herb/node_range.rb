# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    # Utility module for computing byte ranges of Herb AST nodes
    module NodeRange
      # Compute the byte range of an HTML node
      #: (::Herb::AST::HTMLTextNode, ParseResult) -> ::Herb::Range
      #: (html_node) -> ::Herb::Range
      def self.compute(node, parse_result = nil) # rubocop:disable Metrics/AbcSize
        case node
        when ::Herb::AST::HTMLElementNode
          from = node.open_tag.tag_opening.range.from
          to = node.close_tag ? node.close_tag.tag_closing.range.to : node.open_tag.tag_closing.range.to
          ::Herb::Range.new(from, to)
        when ::Herb::AST::HTMLTextNode
          parse_result.location_to_range(node.location)
        when ::Herb::AST::HTMLOpenTagNode, ::Herb::AST::HTMLCloseTagNode
          ::Herb::Range.new(node.tag_opening.range.from, node.tag_closing.range.to)
        when ::Herb::AST::HTMLCommentNode
          ::Herb::Range.new(node.comment_start.range.from, node.comment_end.range.to)
        end
      end
    end
  end
end
