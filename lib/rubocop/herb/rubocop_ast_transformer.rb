# frozen_string_literal: true

require "parser"

module RuboCop
  module Herb
    # Visitor that makes nodes rendered from HTML unique so that they never compare equal
    # Uses Parser::AST::Processor to traverse and transform the AST
    class RuboCopASTTransformer < Parser::AST::Processor
      # Transform AST to make nodes rendered from HTML unique
      # @rbs ast: Parser::AST::Node
      # @rbs parse_result: ParseResult
      def self.transform(ast, parse_result) #: Parser::AST::Node?
        new(parse_result).process(ast)
      end

      attr_reader :parse_result #: ParseResult

      # @rbs parse_result: ParseResult
      def initialize(parse_result) #: void
        @parse_result = parse_result
        super()
      end

      # Process send nodes which represent HTML tags (e.g., div, p)
      # @rbs node: Parser::AST::Node
      def on_send(node) #: Parser::AST::Node
        uniquify_html_method_name(super)
      end

      private

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
        range = parse_result.erb_tag_ranges.bsearch { _1.to > pos }
        range.nil? || pos < range.from
      end
    end
  end
end
