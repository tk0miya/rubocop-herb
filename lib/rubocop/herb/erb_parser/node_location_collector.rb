# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    # Visitor that collects ERB locations in a single AST traversal.
    class NodeLocationCollector < ::Herb::Visitor
      NODE_TYPE_MAP = { #: Hash[Class, ErbLocation::erb_node_type]
        ::Herb::AST::ERBBlockNode => :block,
        ::Herb::AST::ERBIfNode => :if,
        ::Herb::AST::ERBUnlessNode => :unless,
        ::Herb::AST::ERBElseNode => :else,
        ::Herb::AST::ERBCaseNode => :case,
        ::Herb::AST::ERBWhenNode => :when,
        ::Herb::AST::ERBCaseMatchNode => :case_match,
        ::Herb::AST::ERBInNode => :in,
        ::Herb::AST::ERBForNode => :for,
        ::Herb::AST::ERBWhileNode => :while,
        ::Herb::AST::ERBUntilNode => :until,
        ::Herb::AST::ERBBeginNode => :begin,
        ::Herb::AST::ERBRescueNode => :rescue,
        ::Herb::AST::ERBEnsureNode => :ensure,
        ::Herb::AST::ERBYieldNode => :yield,
        ::Herb::AST::ERBCommentNode => :comment,
        ::Herb::AST::ERBEndNode => :end
      }.freeze

      # Result of collecting node locations
      Result = Data.define(
        :erb_locations,  #: Hash[Integer, ErbLocation]
        :erb_positions,  #: Array[Integer] -- start positions of the ERB locations in ascending order
        :erb_tag_ranges  #: Array[CharRange] -- character ranges of ERB tags (from "<%" to "%>") sorted by position
      )

      # Collect ERB locations from a parse result
      # @rbs source: Source
      # @rbs ast: ::Herb::ParseResult
      def self.collect(source, ast) #: Result
        collector = new(source:)
        ast.visit(collector)

        Result.new(
          erb_locations: collector.erb_locations,
          erb_positions: collector.erb_positions,
          erb_tag_ranges: collector.erb_tag_ranges
        )
      end

      attr_reader :source #: Source
      attr_reader :erb_locations #: Hash[Integer, ErbLocation]
      attr_reader :erb_positions #: Array[Integer] -- start positions of the ERB locations in ascending order

      # @rbs source: Source
      def initialize(source:) #: void
        @erb_locations = {}
        @erb_positions = []
        @source = source

        super()
      end

      # Character ranges of ERB tags (from "<%" to "%>") sorted by position
      def erb_tag_ranges #: Array[CharRange]
        ranges = erb_locations.values.map do |loc|
          node = loc.node #: erb_node
          tag_char_range(node)
        end
        ranges.sort_by(&:from)
      end

      # Escaped ERB tags (e.g. `<%% x %>`) are text, so they are not recorded as ERB locations.
      # Their children (e.g. the body of `<%% if x %>`) are visited as usual
      # @rbs node: ::Herb::AST::Node
      def visit_child_nodes(node) #: void
        if erb_node?(node) && !ErbNode.escaped?(node)
          erb = node #: erb_node
          record_erb_location(erb)
        end
        super
      end

      private

      # @rbs node: ::Herb::AST::Node
      def erb_node?(node) #: bool
        node.class.name.not_nil!.start_with?("Herb::AST::ERB")
      end

      # Record the location of an ERB node
      # @rbs node: erb_node
      def record_erb_location(node) #: void
        type = determine_type(node)
        range = NodeRange.compute_char_range(node, source)
        line = node.location.start.line
        column = node.location.start.column

        record_erb_position(range.from) unless erb_locations.key?(range.from)
        erb_locations[range.from] = ErbLocation.new(type:, node:, range:, line:, column:)
      end

      # Insert the position keeping erb_positions sorted
      # ERB nodes are usually visited in the order of their positions, so the position is appended in most cases
      # @rbs pos: Integer
      def record_erb_position(pos) #: void
        index = erb_positions.bsearch_index { _1 > pos } || erb_positions.size
        erb_positions.insert(index, pos)
      end

      # Determine the type of an ERB node
      # @rbs node: erb_node
      def determine_type(node) #: ErbLocation::erb_node_type
        case node
        when ::Herb::AST::ERBContentNode
          ErbLocation::OUTPUT_TAG_OPENINGS.include?(node.tag_opening.not_nil!.value) ? :output : :content
        else
          NODE_TYPE_MAP.fetch(node.class)
        end
      end

      # Character range of the ERB tag of the node (from "<%" to "%>")
      # A node split from an ERB tag (e.g. `<% else; end %>`) or an unclosed ERB tag lacks its tag opening
      # or closing, so its content is used instead
      # @rbs node: erb_node
      def tag_char_range(node) #: CharRange
        from = (node.tag_opening || node.content).not_nil!.range.from
        to = (node.tag_closing || node.content).not_nil!.range.to
        NodeRange.byte_range_to_char_range(::Herb::Range.new(from, to), source)
      end
    end
  end
end
