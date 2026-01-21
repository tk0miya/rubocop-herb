# frozen_string_literal: true

module RuboCop
  module Herb
    # Context for tracking the current block during ERB rendering
    class BlockContext
      attr_reader :statements #: Array[::Herb::AST::Node]
      attr_reader :returning_value #: bool
      attr_reader :html_visualization #: bool
      attr_reader :source #: Source?

      # @rbs statements: Array[::Herb::AST::Node]
      # @rbs returning_value: bool
      # @rbs html_visualization: bool
      # @rbs source: Source?
      def initialize(statements, returning_value:, html_visualization: false, source: nil) #: void
        @statements = statements
        @returning_value = returning_value
        @html_visualization = html_visualization
        @source = source
        @last_erb_node = find_last_erb_node(statements)
      end

      # Check if the given node is the last ERB statement in this block
      # @rbs node: ::Herb::AST::Node
      def last_statement?(node) #: bool
        @last_erb_node == node
      end

      private

      # Recursively find the last ERB node in statements, including inside HTML elements.
      # When html_visualization is enabled, returns nil if HTML nodes follow the last ERB node,
      # because HTML is rendered as Ruby code and the ERB output would not be the tail expression.
      # @rbs statements: Array[::Herb::AST::Node]
      def find_last_erb_node(statements) #: ::Herb::AST::Node?
        statements.reverse_each do |node|
          result = process_node_for_last_erb(node)
          return result if result
          return nil if html_visualization && renders_as_ruby?(node)
        end
        nil
      end

      # Process a single node when searching for last ERB node
      # Returns the ERB node if found, nil to continue searching
      # @rbs node: ::Herb::AST::Node
      def process_node_for_last_erb(node) #: ::Herb::AST::Node?
        # Direct ERB node
        return node if node.class.name.start_with?("Herb::AST::ERB")

        # Search inside HTML elements (ERB wrapped in HTML like <li><%= x %></li>)
        return unless node.is_a?(::Herb::AST::HTMLElementNode) && node.body

        find_last_erb_node(node.body)
      end

      # Check if the node will be rendered as Ruby code when html_visualization is enabled
      # @rbs node: ::Herb::AST::Node
      def renders_as_ruby?(node) #: bool
        return true if node.is_a?(::Herb::AST::HTMLElementNode)
        return true if node.is_a?(::Herb::AST::HTMLTextNode) && contains_non_whitespace?(node)

        false
      end

      # Check if an HTML text node contains non-whitespace characters
      # @rbs node: ::Herb::AST::HTMLTextNode
      def contains_non_whitespace?(node) #: bool
        return false unless source

        range = source.location_to_range(node.location)
        source.byteslice(range).match?(/\S/)
      end
    end
  end
end
