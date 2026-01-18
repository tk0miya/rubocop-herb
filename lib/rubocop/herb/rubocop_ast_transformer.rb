# frozen_string_literal: true

require "parser"

module RuboCop
  module Herb
    # Visitor that restores original HTML tag information in AST nodes
    # Uses Parser::AST::Processor to traverse and transform the AST
    class RuboCopASTTransformer < Parser::AST::Processor
      # Transform AST to restore original HTML tag information
      # @rbs ast: Parser::AST::Node
      # @rbs html_tags: Hash[Integer, HtmlTag]
      # @rbs buffer: Parser::Source::Buffer
      def self.transform(ast, html_tags, buffer) #: Parser::AST::Node
        new(html_tags, buffer).process(ast)
      end

      attr_reader :buffer #: Parser::Source::Buffer
      attr_reader :html_tags #: Hash[Integer, HtmlTag]

      # @rbs html_tags: Hash[Integer, HtmlTag]
      # @rbs buffer: Parser::Source::Buffer
      def initialize(html_tags, buffer) #: void
        @html_tags = html_tags
        @buffer = buffer
        super()
      end

      # Process send nodes which represent HTML tags (e.g., div, p0)
      # @rbs node: RuboCop::AST::SendNode
      def on_send(node) #: RuboCop::AST::SendNode
        new_node = super
        restore_html_location(new_node)
      end

      private

      # Restore HTML location if this node matches an HTML tag
      # @rbs node: Parser::AST::Node
      def restore_html_location(node) #: Parser::AST::Node
        return node unless node.location&.expression

        html_tag = html_tags[node.location.expression.begin_pos]
        return node unless html_tag

        location = build_html_location(node, html_tag)
        node.updated(nil, nil, location:)
      end

      # Build a new location map with HTML source buffer
      # @rbs node: Parser::AST::Node
      # @rbs html_tag: HtmlTag
      def build_html_location(node, html_tag) #: Parser::Source::Map
        range = Parser::Source::Range.new(buffer, html_tag.range.from, html_tag.range.to)

        case node.location
        when Parser::Source::Map::Send
          Parser::Source::Map::Send.new(nil, range, nil, nil, range)
        else
          Parser::Source::Map.new(range)
        end
      end
    end
  end
end
