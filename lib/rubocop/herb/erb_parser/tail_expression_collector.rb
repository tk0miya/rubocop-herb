# frozen_string_literal: true

require "herb"
require_relative "block_context"

module RuboCop
  module Herb
    # Visitor that collects tail expression positions from an ERB document.
    # A tail expression is an output node (<%= %>) that is the last statement
    # in a returning_value block (if/unless/else/when/begin/rescue/ensure).
    # These nodes don't need the `_ =` marker because their value is returned
    # as part of the control flow.
    class TailExpressionCollector < ::Herb::Visitor
      # Collect tail expression positions from a parse result
      # @rbs ast: ::Herb::ParseResult
      # @rbs html_block_positions: Set[Integer]
      def self.collect(ast, html_block_positions) #: Set[Integer]
        collector = new(html_block_positions)
        ast.visit(collector)
        collector.tail_expressions
      end

      attr_reader :tail_expressions #: Set[Integer]
      attr_reader :html_block_positions #: Set[Integer]
      attr_reader :block_stack #: Array[BlockContext]

      # @rbs html_block_positions: Set[Integer]
      def initialize(html_block_positions) #: void
        @tail_expressions = Set.new
        @html_block_positions = html_block_positions
        @block_stack = []

        super()
      end

      # @rbs!
      #   def visit_erb_block_node: (::Herb::AST::ERBBlockNode node) -> void
      #   def visit_erb_for_node: (::Herb::AST::ERBForNode node) -> void
      #   def visit_erb_while_node: (::Herb::AST::ERBWhileNode node) -> void
      #   def visit_erb_until_node: (::Herb::AST::ERBUntilNode node) -> void
      #   def visit_erb_if_node: (::Herb::AST::ERBIfNode node) -> void
      #   def visit_erb_unless_node: (::Herb::AST::ERBUnlessNode node) -> void
      #   def visit_erb_else_node: (::Herb::AST::ERBElseNode node) -> void
      #   def visit_erb_when_node: (::Herb::AST::ERBWhenNode node) -> void
      #   def visit_erb_begin_node: (::Herb::AST::ERBBeginNode node) -> void
      #   def visit_erb_rescue_node: (::Herb::AST::ERBRescueNode node) -> void
      #   def visit_erb_ensure_node: (::Herb::AST::ERBEnsureNode node) -> void

      # ERB block nodes use node.body for statements
      %i[block].each do |type|
        define_method(:"visit_erb_#{type}_node") do |node|
          push_block(node.body)
          super(node)
          pop_block
        end
      end

      # Loop nodes: return value is discarded
      %i[for while until].each do |type|
        define_method(:"visit_erb_#{type}_node") do |node|
          push_block(node.statements)
          super(node)
          pop_block
        end
      end

      # Control flow nodes: returns value
      %i[if unless else when begin rescue ensure].each do |type|
        define_method(:"visit_erb_#{type}_node") do |node|
          push_block(node.statements, returning_value: true)
          super(node)
          pop_block
        end
      end

      # Visit ERB content nodes (the actual Ruby code: <% %> or <%= %>)
      # @rbs node: ::Herb::AST::ERBContentNode
      def visit_erb_content_node(node) #: void
        record_tail_expression(node) if output_node?(node) && tail_expression?(node)
        super
      end

      # Visit ERB yield nodes (<%= yield %> or <%= yield(...) %>)
      # @rbs node: ::Herb::AST::ERBYieldNode
      def visit_erb_yield_node(node) #: void
        record_tail_expression(node) if tail_expression?(node)
        super
      end

      # Visit HTML element nodes
      # When using brace notation, push a block context so that ERB nodes inside
      # are not treated as tail expressions of outer blocks (HTML blocks don't return values)
      # @rbs node: ::Herb::AST::HTMLElementNode
      def visit_html_element_node(node) #: void
        as_brace = html_block_positions.include?(node.open_tag.tag_opening.range.from)
        if as_brace
          push_block(node.body || [])
          super
          pop_block
        else
          super
        end
      end

      private

      # @rbs statements: Array[::Herb::AST::Node]
      # @rbs returning_value: bool
      def push_block(statements, returning_value: false) #: void
        block_stack.push(BlockContext.new(statements, returning_value:))
      end

      def pop_block #: void
        block_stack.pop
      end

      def current_block #: BlockContext?
        block_stack.last
      end

      # @rbs node: ::Herb::AST::ERBContentNode
      def output_node?(node) #: bool
        node.tag_opening.value == "<%="
      end

      # Check if this node is a tail expression
      # @rbs node: ::Herb::AST::Node
      def tail_expression?(node) #: bool
        return false unless current_block
        return false unless current_block.returning_value
        return false unless current_block.last_statement?(node)

        true
      end

      # Record a tail expression position
      # @rbs node: ::Herb::AST::Node
      def record_tail_expression(node) #: void
        tail_expressions.add(node.tag_opening.range.from)
      end
    end
  end
end
