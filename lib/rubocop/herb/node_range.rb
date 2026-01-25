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

      # Compute the character range of an HTML node
      # @rbs node: html_node
      # @rbs source: Source
      def self.compute_char_range(node, source) #: CharRange
        byte_range = compute(node, source)
        byte_range_to_char_range(byte_range, source)
      end

      # Convert a Herb::Range (byte-based) to a CharRange (character-based)
      # @rbs range: ::Herb::Range
      # @rbs source: Source
      def self.byte_range_to_char_range(range, source) #: CharRange
        CharRange.new(source.byte_to_char_pos(range.from), source.byte_to_char_pos(range.to))
      end

      # Convert a Herb::Location to a CharRange (character-based)
      # @rbs location: ::Herb::Location
      # @rbs source: Source
      def self.location_to_char_range(location, source) #: CharRange
        byte_range = source.location_to_range(location)
        byte_range_to_char_range(byte_range, source)
      end
    end
  end
end
