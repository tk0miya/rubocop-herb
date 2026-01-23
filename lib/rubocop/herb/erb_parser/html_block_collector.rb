# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    # Visitor that collects HTML element positions that can be rendered as Ruby blocks.
    # An element can be rendered as a block when:
    # - It contains ERB nodes
    # - It has a close tag (not a void element like <meta>, <br>)
    # - The open tag has enough space for block notation (tag name + " { ")
    class HtmlBlockCollector < ::Herb::Visitor
      # Collect HTML block positions from an AST
      # @rbs ast: ::Herb::ParseResult
      # @rbs erb_locations: Hash[Integer, ErbLocation]
      def self.collect(ast, erb_locations) #: Set[Integer]
        collector = new(erb_locations)
        ast.visit(collector)
        collector.html_block_positions
      end

      attr_reader :erb_locations #: Hash[Integer, ErbLocation]
      attr_reader :html_block_positions #: Set[Integer]

      # @rbs erb_locations: Hash[Integer, ErbLocation]
      def initialize(erb_locations) #: void
        @erb_locations = erb_locations
        @html_block_positions = Set.new

        super()
      end

      # Visit HTML element nodes and determine if they can be rendered as blocks
      # @rbs node: ::Herb::AST::HTMLElementNode
      def visit_html_element_node(node) #: void
        html_block_positions.add(node.open_tag.tag_opening.range.from) if block_element?(node)
        super
      end

      private

      # Check if this HTML element can be rendered as a Ruby block
      # @rbs node: ::Herb::AST::HTMLElementNode
      def block_element?(node) #: bool
        return false unless node.close_tag
        return false unless contains_erb?(node)
        return false unless fits_block_notation?(node.open_tag)

        true
      end

      # Check if an HTML element contains ERB nodes
      # @rbs node: ::Herb::AST::HTMLElementNode
      def contains_erb?(node) #: bool
        range = NodeRange.compute(node)
        erb_locations.keys.any? { |pos| pos >= range.from && pos < range.to }
      end

      # Check if block notation fits within the open tag space
      # Block notation requires at least 3 bytes beyond tag name for " { "
      # @rbs node: ::Herb::AST::HTMLOpenTagNode
      def fits_block_notation?(node) #: bool
        tag_name = node.tag_name.value
        tag_length = node.tag_closing.range.to - node.tag_opening.range.from
        required_tag_length = tag_name.bytesize + 3 # "tag { " needs tag + " { "
        tag_length >= required_tag_length
      end
    end
  end
end
