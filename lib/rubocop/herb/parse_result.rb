# frozen_string_literal: true

require "forwardable"
require "herb"

module RuboCop
  module Herb
    # Data class holding the results of parsing an ERB file.
    # Contains the parsed AST, collected ERB locations, and precomputed data
    # needed for rendering. Logic is minimal - mostly data access and simple queries.
    ParseResult = Data.define(
      :source,                #: Source
      :ast,                   #: ::Herb::ParseResult
      :erb_locations,         #: Hash[Integer, ErbLocation]
      :erb_max_columns,       #: Hash[Integer, Integer]
      :html_block_positions,  #: Set[::Herb::AST::HTMLElementNode]
      :tail_expressions,      #: Set[::Herb::AST::Node]
      :tags,                  #: Hash[Integer, Tag]
      :disabled_cops          #: Hash[String, Array[Range[Integer]]] -- line ranges where each cop is disabled
    )

    # Methods are defined by reopening the class (not in a Data.define block)
    # so that rbs-inline can generate their type signatures.
    class ParseResult
      extend Forwardable

      # @rbs!
      #   def code: () -> String
      #   def byteslice: (::Herb::Range) -> String
      #   def slice: (CharRange range) -> String

      def_delegators :source, :code, :byteslice, :slice

      # Check if a range contains any ERB nodes
      # @rbs range: CharRange
      def contains_erb?(range) #: bool
        erb_locations.keys.any? { _1 >= range.from && _1 < range.to }
      end

      # Get all ERB comment nodes
      def erb_comment_nodes #: Array[::Herb::AST::ERBCommentNode]
        erb_locations.values.select(&:comment?).map(&:node) #: Array[::Herb::AST::ERBCommentNode]
      end

      # Check if a node is a tail expression (output node at end of returning block)
      # @rbs node: ::Herb::AST::Node
      def tail_expression?(node) #: bool
        tail_expressions.include?(node)
      end
    end
  end
end
