# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    # Visitor that collects ErbLocation objects for all ERB nodes in a document.
    class ErbLocationCollector < ::Herb::Visitor
      NODE_TYPE_MAP = { #: Hash[Class, ErbLocation::erb_node_type]
        ::Herb::AST::ERBBlockNode => :block,
        ::Herb::AST::ERBIfNode => :if,
        ::Herb::AST::ERBUnlessNode => :unless,
        ::Herb::AST::ERBElseNode => :else,
        ::Herb::AST::ERBCaseNode => :case,
        ::Herb::AST::ERBWhenNode => :when,
        ::Herb::AST::ERBForNode => :for,
        ::Herb::AST::ERBWhileNode => :while,
        ::Herb::AST::ERBUntilNode => :until,
        ::Herb::AST::ERBBeginNode => :begin,
        ::Herb::AST::ERBRescueNode => :rescue,
        ::Herb::AST::ERBEnsureNode => :ensure,
        ::Herb::AST::ERBYieldNode => :yield,
        ::Herb::AST::ERBEndNode => :end
      }.freeze

      # Result of collecting ERB locations
      Result = Data.define(
        :locations,        #: Hash[Integer, ErbLocation]
        :erb_max_columns   #: Hash[Integer, Integer]
      )

      # Collect ERB locations from a parse result
      # @rbs parse_result: ::Herb::ParseResult
      def self.collect(parse_result) #: Result
        collector = new
        parse_result.visit(collector)
        Result.new(locations: collector.locations, erb_max_columns: collector.erb_max_columns)
      end

      attr_reader :locations #: Hash[Integer, ErbLocation]
      attr_reader :erb_max_columns #: Hash[Integer, Integer]

      def initialize #: void
        @locations = {}
        @erb_max_columns = {}

        super
      end

      # @rbs node: ::Herb::AST::Node
      def visit_child_nodes(node) #: void
        record_location(node) if erb_node?(node)
        super
      end

      private

      # @rbs node: ::Herb::AST::Node
      def erb_node?(node) #: bool
        node.class.name.start_with?("Herb::AST::ERB")
      end

      # Record the location of an ERB node
      # @rbs node: erb_node
      def record_location(node) #: void
        type = determine_type(node)
        range = ::Herb::Range.new(node.tag_opening.range.from, node.tag_closing.range.to)
        line = node.location.start.line
        column = node.location.start.column

        locations[range.from] = ErbLocation.new(type:, node:, range:, line:, column:)
        update_erb_max_columns(type, line, column)
      end

      # @rbs type: ErbLocation::erb_node_type
      # @rbs line: Integer
      # @rbs column: Integer
      def update_erb_max_columns(type, line, column) #: void
        return if type == :comment

        erb_max_columns[line] = [erb_max_columns[line] || 0, column].max
      end

      # Determine the type of an ERB node
      # @rbs node: erb_node
      def determine_type(node) #: ErbLocation::erb_node_type
        case node
        when ::Herb::AST::ERBContentNode
          case node.tag_opening.value
          when "<%#" then :comment
          when "<%=" then :output
          else :content
          end
        else
          NODE_TYPE_MAP.fetch(node.class)
        end
      end
    end
  end
end
