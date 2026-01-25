# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    # Visitor that collects tail expression positions from an ERB document.
    # A tail expression is an output node (<%= %>) that is the last statement
    # in a returning_value block (if/unless/else/when/begin/rescue/ensure).
    # These nodes don't need the `_ =` marker because their value is returned
    # as part of the control flow.
    class TailExpressionCollector < ::Herb::Visitor
      # Collect tail expression nodes from a parse result
      # @rbs ast: ::Herb::ParseResult
      # @rbs html_block_positions: Set[::Herb::AST::HTMLElementNode]
      # @rbs html_visualization: bool
      def self.collect(ast, html_block_positions, html_visualization:) #: Set[::Herb::AST::Node]
        collector = new(html_block_positions, html_visualization:)
        ast.visit(collector)
        collector.tail_expressions
      end

      attr_reader :tail_expressions #: Set[::Herb::AST::Node]
      attr_reader :html_block_positions #: Set[::Herb::AST::HTMLElementNode]
      attr_reader :html_visualization #: bool
      attr_reader :block_stack #: Array[Array[::Herb::AST::Node]]

      # @rbs html_block_positions: Set[::Herb::AST::HTMLElementNode]
      # @rbs html_visualization: bool
      def initialize(html_block_positions, html_visualization:) #: void
        @tail_expressions = Set.new
        @html_block_positions = html_block_positions
        @html_visualization = html_visualization
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

      # ERB block nodes and loop nodes: return value is discarded
      %i[block for while until].each do |type|
        define_method(:"visit_erb_#{type}_node") do |node|
          record_node(node)
          push_block
          super(node)
          pop_block
        end
      end

      # Control flow nodes that start a statement: returns value, so last output is tail expression
      %i[if unless begin case].each do |type|
        define_method(:"visit_erb_#{type}_node") do |node|
          record_node(node)
          push_block
          super(node)
          pop_block(returning_value: true)
        end
      end

      # Control flow branch nodes: internal to parent statement, not recorded in grandparent
      %i[else when rescue ensure].each do |type|
        define_method(:"visit_erb_#{type}_node") do |node|
          push_block
          super(node)
          pop_block(returning_value: true)
        end
      end

      # Visit ERB content nodes (the actual Ruby code: <% %> or <%= %>)
      # @rbs node: ::Herb::AST::ERBContentNode
      def visit_erb_content_node(node) #: void
        record_node(node)
        super
      end

      # Visit ERB yield nodes (<%= yield %> or <%= yield(...) %>)
      # @rbs node: ::Herb::AST::ERBYieldNode
      def visit_erb_yield_node(node) #: void
        record_node(node)
        super
      end

      # Visit HTML element nodes
      # When html_visualization is enabled, HTML elements generate Ruby code and are recorded.
      # When using brace notation, push a block context so that ERB nodes inside
      # are not treated as tail expressions of outer blocks (HTML blocks don't return values)
      # For non-brace elements with closing tags, the closing tag is also recorded as it
      # generates Ruby code (e.g., div0;) that comes after any ERB inside the element.
      # @rbs node: ::Herb::AST::HTMLElementNode
      def visit_html_element_node(node) #: void
        return super unless html_visualization

        record_node(node.open_tag)
        if html_block_positions.include?(node)
          push_block
          super
          pop_block
        else
          super
          # Record close tag for non-brace elements (rendered as tagN;)
          record_node(node.close_tag) if node.close_tag
        end
      end

      private

      def push_block #: void
        block_stack.push([])
      end

      # @rbs returning_value: bool
      def pop_block(returning_value: false) #: void
        nodes = block_stack.pop
        return unless returning_value

        last_node = nodes&.last
        return unless last_node

        tail_expressions.add(last_node)
      end

      # @rbs node: ::Herb::AST::Node
      def record_node(node) #: void
        block_stack.last&.push(node)
      end
    end
  end
end
