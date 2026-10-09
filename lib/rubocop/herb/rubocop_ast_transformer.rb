# frozen_string_literal: true

require "parser"

module RuboCop
  module Herb
    # Visitor that restores original HTML tag information in AST nodes
    # and makes nodes rendered from HTML unique so that they never compare equal
    # Uses Parser::AST::Processor to traverse and transform the AST
    class RuboCopASTTransformer < Parser::AST::Processor
      # Transform AST to restore original HTML tag information
      # @rbs ast: Parser::AST::Node
      # @rbs parse_result: ParseResult
      def self.transform(ast, parse_result) #: Parser::AST::Node?
        new(parse_result).process(ast)
      end

      attr_reader :parse_result #: ParseResult

      # @rbs @erb_tag_ranges: Array[CharRange]

      # @rbs parse_result: ParseResult
      def initialize(parse_result) #: void
        @parse_result = parse_result
        super()
      end

      # Process send nodes which represent HTML tags (e.g., div, p0)
      # @rbs node: Parser::AST::Node
      def on_send(node) #: Parser::AST::Node
        new_node = super
        uniquify_html_method_name(restore_html_location(new_node))
      end

      private

      # Restore HTML location if this node matches an HTML tag
      # @rbs node: Parser::AST::Node
      def restore_html_location(node) #: Parser::AST::Node
        return node unless node.location&.expression

        tag = parse_result.tags[node.location.expression.begin_pos]
        return node unless tag

        location = build_html_location(node, tag)
        node.updated(nil, nil, location:)
      end

      # Rename the method of a node rendered from HTML to be unique per position
      # so that HTML nodes never compare equal
      # (e.g. in Lint/DuplicateBranch and Style/IdenticalConditionalBranches)
      # @rbs node: Parser::AST::Node
      def uniquify_html_method_name(node) #: Parser::AST::Node
        pos = node.location&.expression&.begin_pos
        return node unless pos && html_code?(pos)

        receiver, method_name, *args = node.children
        node.updated(nil, [receiver, :"#{method_name}__html#{pos}", *args])
      end

      # Check if the code at the position is rendered from HTML (i.e. outside of ERB tags)
      # @rbs pos: Integer
      def html_code?(pos) #: bool
        range = erb_tag_ranges.bsearch { _1.to > pos }
        range.nil? || pos < range.from
      end

      # Character ranges of ERB tags (from "<%" to "%>") sorted by position
      def erb_tag_ranges #: Array[CharRange]
        @erb_tag_ranges ||= parse_result.erb_locations.values.map { erb_tag_range(_1) }.sort_by(&:from)
      end

      # Character range of an ERB tag
      # A node split from an ERB tag (e.g. `<% else; end %>`) or an unclosed ERB tag lacks its tag opening
      # or closing, so its content is used instead
      # @rbs loc: ErbLocation
      def erb_tag_range(loc) #: CharRange
        node = loc.node #: erb_node
        from = (node.tag_opening || node.content).not_nil!.range.from
        to = (node.tag_closing || node.content).not_nil!.range.to
        NodeRange.byte_range_to_char_range(::Herb::Range.new(from, to), parse_result.source)
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
    end
  end
end
