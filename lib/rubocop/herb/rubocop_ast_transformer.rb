# frozen_string_literal: true

require "parser"

module RuboCop
  module Herb
    # Visitor that restores original HTML tag information in AST nodes
    # Uses Parser::AST::Processor to traverse and transform the AST
    class RuboCopASTTransformer < Parser::AST::Processor
      # Transform AST to restore original HTML tag information
      # @rbs ast: Parser::AST::Node
      # @rbs tags: Hash[Integer, Tag]
      def self.transform(ast, tags) #: Parser::AST::Node
        new(tags).process(ast)
      end

      attr_reader :tags #: Hash[Integer, Tag]

      # @rbs tags: Hash[Integer, Tag]
      def initialize(tags) #: void
        @tags = tags
        super()
      end

      # Process send nodes which represent HTML tags (e.g., div, p0)
      # @rbs node: RuboCop::AST::SendNode
      def on_send(node) #: RuboCop::AST::SendNode
        new_node = super
        restore_html_location(new_node)
      end

      # Process if nodes to restore ERB tag locations
      # @rbs node: RuboCop::AST::IfNode
      def on_if(node) #: RuboCop::AST::IfNode
        new_node = super
        restore_erb_if_location(new_node)
      end

      private

      # Restore HTML location if this node matches an HTML tag
      # @rbs node: Parser::AST::Node
      def restore_html_location(node) #: Parser::AST::Node
        return node unless node.location&.expression

        tag = tags[node.location.expression.begin_pos]
        return node unless tag

        location = build_html_location(node, tag)
        node.updated(nil, nil, location:)
      end

      # Build a new location map with HTML source range
      # @rbs node: Parser::AST::Node
      # @rbs tag: Tag
      def build_html_location(node, tag) #: Parser::Source::Map
        buffer = node.location.expression.source_buffer
        range = Parser::Source::Range.new(buffer, tag.range.from, tag.range.to)

        case node.location
        when Parser::Source::Map::Send
          Parser::Source::Map::Send.new(nil, range, nil, nil, range)
        else
          Parser::Source::Map.new(range)
        end
      end

      # Restore ERB if/end tag locations (keyword, else, end, and expression)
      # Uses monkey-patched if?/is? methods to handle ERB-wrapped keywords
      # @rbs node: Parser::AST::Node
      def restore_erb_if_location(node) #: Parser::AST::Node
        case node.location
        when Parser::Source::Map::Condition
          restore_erb_condition_location(node)
        else
          node
        end
      end

      # @rbs node: Parser::AST::Node
      def restore_erb_condition_location(node) #: Parser::AST::Node
        loc = node.location #: Parser::Source::Map::Condition
        return node unless loc.keyword

        erb_tags = collect_erb_if_tags(loc)
        return node if erb_tags.values.none?

        location = build_erb_if_location(node, **erb_tags)
        node.updated(nil, nil, location:)
      end

      # Collect ERB tags for keyword, else, and end positions
      # @rbs loc: Parser::Source::Map::Condition
      def collect_erb_if_tags(loc) #: Hash[Symbol, Tag?]
        {
          keyword_tag: tags[loc.keyword.begin_pos],
          else_tag: loc.else ? tags[loc.else.begin_pos] : nil,
          end_tag: loc.end ? tags[loc.end.begin_pos] : nil
        }
      end

      # Build a new location map with adjusted keyword, else, end, and expression ranges
      # @rbs node: Parser::AST::Node
      # @rbs keyword_tag: Tag?
      # @rbs else_tag: Tag?
      # @rbs end_tag: Tag?
      def build_erb_if_location(node, keyword_tag:, else_tag:, end_tag:) #: Parser::Source::Map::Condition
        loc = node.location
        buffer = loc.expression.source_buffer

        new_keyword = build_erb_range(buffer, loc.keyword, keyword_tag)
        new_else = loc.else ? build_erb_range(buffer, loc.else, else_tag) : nil
        new_end = loc.end ? build_erb_range(buffer, loc.end, end_tag) : nil

        # Adjust expression: from keyword start to end (or expression end if no end tag)
        expression_end = new_end ? new_end.end_pos : loc.expression.end_pos
        new_expression = Parser::Source::Range.new(buffer, new_keyword.begin_pos, expression_end)

        Parser::Source::Map::Condition.new(new_keyword, loc.begin, new_else, new_end, new_expression)
      end

      # Build an ERB-adjusted range from original range and tag info
      # @rbs buffer: Parser::Source::Buffer
      # @rbs original: Parser::Source::Range
      # @rbs tag: Tag?
      def build_erb_range(buffer, original, tag) #: Parser::Source::Range
        if tag
          Parser::Source::Range.new(buffer, tag.range.from, tag.range.to)
        else
          original
        end
      end
    end
  end
end
