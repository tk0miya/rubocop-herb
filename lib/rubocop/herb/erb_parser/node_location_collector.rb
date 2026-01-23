# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    # Visitor that collects both ERB locations and HTML block positions in a single AST traversal.
    # Combines the functionality of ErbLocationCollector and HtmlBlockCollector.
    class NodeLocationCollector < ::Herb::Visitor
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

      # Result of collecting node locations
      Result = Data.define(
        :erb_locations,        #: Hash[Integer, ErbLocation]
        :erb_max_columns,      #: Hash[Integer, Integer]
        :html_block_positions  #: Set[Integer]
      )

      # Collect ERB locations and HTML block positions from a parse result
      # @rbs parse_result: ::Herb::ParseResult
      def self.collect(parse_result) #: Result
        collector = new
        parse_result.visit(collector)
        Result.new(
          erb_locations: collector.erb_locations,
          erb_max_columns: collector.erb_max_columns,
          html_block_positions: collector.html_block_positions
        )
      end

      attr_reader :erb_locations #: Hash[Integer, ErbLocation]
      attr_reader :erb_max_columns #: Hash[Integer, Integer]
      attr_reader :html_block_positions #: Set[Integer]

      def initialize #: void
        @erb_locations = {}
        @erb_max_columns = {}
        @html_block_positions = Set.new

        super
      end

      # @rbs node: ::Herb::AST::Node
      def visit_child_nodes(node) #: void
        record_erb_location(node) if erb_node?(node)
        super
      end

      # Visit HTML element nodes and determine if they can be rendered as blocks
      # super is called first to traverse children and collect ERB locations,
      # then we check if this element qualifies as a block element.
      # @rbs node: ::Herb::AST::HTMLElementNode
      def visit_html_element_node(node) #: void
        super
        html_block_positions.add(node.open_tag.tag_opening.range.from) if block_html_element?(node)
      end

      private

      # @rbs node: ::Herb::AST::Node
      def erb_node?(node) #: bool
        node.class.name.start_with?("Herb::AST::ERB")
      end

      # Record the location of an ERB node
      # @rbs node: erb_node
      def record_erb_location(node) #: void
        type = determine_type(node)
        range = ::Herb::Range.new(node.tag_opening.range.from, node.tag_closing.range.to)
        line = node.location.start.line
        column = node.location.start.column

        erb_locations[range.from] = ErbLocation.new(type:, node:, range:, line:, column:)
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

      # Check if this HTML element can be rendered as a Ruby block
      # @rbs node: ::Herb::AST::HTMLElementNode
      def block_html_element?(node) #: bool
        return false unless node.close_tag
        return false unless contains_erb?(node)
        return false unless fits_block_notation?(node.open_tag)

        true
      end

      # Check if an HTML element contains ERB nodes
      # @rbs node: ::Herb::AST::HTMLElementNode
      def contains_erb?(node) #: bool
        range = NodeRange.compute(node)
        erb_locations.keys.any? { |pos| pos >= range.from && pos < range.to }
      end

      # Check if block notation fits within the open tag space
      # Block notation requires at least 3 bytes beyond tag name for " { "
      # @rbs node: ::Herb::AST::HTMLOpenTagNode
      def fits_block_notation?(node) #: bool
        tag_name = node.tag_name.value
        tag_length = node.tag_closing.range.to - node.tag_opening.range.from
        required_tag_length = tag_name.bytesize + 3 # "tag { " needs tag + " { "
        tag_length >= required_tag_length
      end
    end
  end
end
