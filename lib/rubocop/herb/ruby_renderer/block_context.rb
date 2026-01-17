# frozen_string_literal: true

module RuboCop
  module Herb
    # Context for tracking the current block during ERB rendering
    class BlockContext
      attr_reader :statements #: Array[::Herb::AST::Node]
      attr_reader :returning_value #: bool

      # @rbs statements: Array[::Herb::AST::Node]
      # @rbs returning_value: bool
      def initialize(statements, returning_value:) #: void
        @statements = statements
        @returning_value = returning_value
        @last_erb_node = find_last_erb_node(statements)
      end

      # Check if the given node is the last ERB statement in this block
      # @rbs node: ::Herb::AST::Node
      def last_statement?(node) #: bool
        @last_erb_node == node
      end

      private

      # @rbs statements: Array[::Herb::AST::Node]
      def find_last_erb_node(statements) #: ::Herb::AST::Node?
        statements.reverse.find { |s| s.class.name.start_with?("Herb::AST::ERB") }
      end
    end
  end
end
