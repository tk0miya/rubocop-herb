# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    # Utility module for computing byte ranges of Herb AST nodes
    module NodeRange
      # Compute the character range of an AST node
      # @rbs node: ::Herb::AST::Node
      # @rbs source: Source
      def self.compute_char_range(node, source) #: CharRange
        byte_range = source.location_to_range(node.location)
        byte_range_to_char_range(byte_range, source)
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
