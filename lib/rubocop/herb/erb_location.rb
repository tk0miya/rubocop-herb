# frozen_string_literal: true

module RuboCop
  module Herb
    # Represents the location and metadata of an ERB node
    class ErbLocation
      # @rbs!
      #   type erb_node_type = :content | :output | :comment
      #                      | :block | :if | :unless | :else
      #                      | :case | :when
      #                      | :for | :while | :until
      #                      | :begin | :rescue | :ensure
      #                      | :yield | :end

      attr_reader :type   #: erb_node_type
      attr_reader :node   #: ::Herb::AST::Node
      attr_reader :range  #: ::Herb::Range
      attr_reader :line   #: Integer -- 1-indexed line number
      attr_reader :column #: Integer -- 0-indexed column number

      # @rbs type: erb_node_type
      # @rbs node: ::Herb::AST::Node
      # @rbs range: ::Herb::Range
      # @rbs line: Integer
      # @rbs column: Integer
      def initialize(type:, node:, range:, line:, column:) #: void
        @type = type
        @node = node
        @range = range
        @line = line
        @column = column
      end

      # Check if this is an output node (<%= %>)
      def output? #: bool
        type == :output
      end

      # Check if this is a comment node (<%# %>)
      def comment? #: bool
        type == :comment
      end
    end
  end
end
