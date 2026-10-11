# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    # Utility module for computing character ranges (`CharRange`) of Herb AST nodes
    module NodeRange
      # Compute the character range of an AST node
      # @rbs node: ::Herb::AST::Node
      # @rbs source: Source
      def self.compute_char_range(node, source) #: CharRange
        location = node.location
        CharRange.new(source.char_pos(location.start.line, location.start.column),
                      source.char_pos(location.end.line, location.end.column))
      end

      # Convert a Herb::Range (byte-based) to a CharRange (character-based)
      # @rbs range: ::Herb::Range
      # @rbs source: Source
      def self.byte_range_to_char_range(range, source) #: CharRange
        CharRange.new(source.byte_to_char_pos(range.from), source.byte_to_char_pos(range.to))
      end
    end
  end
end
