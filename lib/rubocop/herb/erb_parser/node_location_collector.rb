# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    # Visitor that collects both ERB locations and HTML block positions in a single AST traversal.
    # Combines the functionality of ErbLocationCollector and HtmlBlockCollector.
    # Also collects HTML tags when html_visualization is enabled.
    class NodeLocationCollector < ::Herb::Visitor # rubocop:disable Metrics/ClassLength
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
        :html_block_positions, #: Set[Integer]
        :tags                  #: Hash[Integer, Tag]
      )

      # Collect ERB locations, HTML block positions, and tags from a parse result
      # @rbs source: Source
      # @rbs ast: ::Herb::ParseResult
      # @rbs html_visualization: bool
      def self.collect(source, ast, html_visualization: false) #: Result
        collector = new(source:, html_visualization:)
        ast.visit(collector)

        erb_tags = collector.erb_locations.to_h do |_, loc|
          range = NodeRange.byte_range_to_char_range(loc.range, source)
          [range.from, Tag.new(range:, restore_source: false)]
        end

        Result.new(
          erb_locations: collector.erb_locations,
          erb_max_columns: collector.erb_max_columns,
          html_block_positions: collector.html_block_positions,
          tags: erb_tags.merge(collector.tags)
        )
      end

      attr_reader :source #: Source
      attr_reader :html_visualization #: bool
      attr_reader :erb_locations #: Hash[Integer, ErbLocation]
      attr_reader :erb_max_columns #: Hash[Integer, Integer]
      attr_reader :html_block_positions #: Set[Integer]
      attr_reader :tags #: Hash[Integer, Tag]

      # @rbs source: Source
      # @rbs html_visualization: bool
      def initialize(source:, html_visualization:) #: void
        @erb_locations = {}
        @erb_max_columns = {}
        @html_block_positions = Set.new
        @tags = {}
        @source = source
        @html_visualization = html_visualization

        super()
      end

      # @rbs node: ::Herb::AST::Node
      def visit_child_nodes(node) #: void
        record_erb_location(node) if erb_node?(node)
        super
      end

      # Visit HTML element nodes and determine if they can be rendered as blocks.
      # Also collects tag info when html_visualization is enabled.
      # super is called first to traverse children and collect ERB locations,
      # then we check if this element qualifies as a block element.
      # Block positions are only collected when html_visualization is enabled,
      # otherwise TailExpressionCollector would incorrectly capture output nodes
      # inside HTML elements instead of the outer ERB control flow context.
      # @rbs node: ::Herb::AST::HTMLElementNode
      def visit_html_element_node(node) #: void
        super
        return unless html_visualization

        html_block_positions.add(node.open_tag.tag_opening.range.from) if block_html_element?(node)
        record_html_element_tag(node)
      end

      # Visit HTML text nodes and collect tag info when html_visualization is enabled
      # @rbs node: ::Herb::AST::HTMLTextNode
      def visit_html_text_node(node) #: void
        super
        record_text_node_tag(node) if html_visualization
      end

      # Visit HTML comment nodes and collect tag info when html_visualization is enabled
      # super is called first to traverse children and collect ERB locations,
      # then we check if this comment contains ERB to decide whether to record tag info.
      # Comments containing ERB are not recorded (they are visited normally to traverse children)
      # @rbs node: ::Herb::AST::HTMLCommentNode
      def visit_html_comment_node(node) #: void
        super
        return if contains_erb?(node)

        record_html_comment_tag(node) if html_visualization
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

      # Record tag info for HTML elements
      # For elements with ERB: record open_tag (if it doesn't contain ERB) and close_tag
      # For elements without ERB: record the whole element
      # @rbs node: ::Herb::AST::HTMLElementNode
      def record_html_element_tag(node) #: void
        if contains_erb?(node)
          # Only restore open tag if it doesn't contain ERB (e.g., ERB in attributes)
          # Restoring tags with ERB causes false positives in Layout/SpaceAroundOperators
          record_tag(node.open_tag) unless contains_erb?(node.open_tag)
          record_tag(node.close_tag) if node.close_tag
        else
          record_tag(node)
        end
      end

      # Record tag info for text nodes
      # Text nodes with multi-byte characters are skipped
      # @rbs node: ::Herb::AST::HTMLTextNode
      def record_text_node_tag(node) #: void
        range = NodeRange.location_to_char_range(node.location, source)
        text = source.slice(range)

        # Must have non-whitespace content and enough space for marker
        match = text.match(/\S/)
        return unless match

        pos = range.from + match.begin(0)
        return unless pos + 4 <= range.to

        # Skip recording tag info for text with multi-byte characters
        # Multi-byte chars are bleached to multiple spaces, changing character count
        # If we restore the original text, character positions would mismatch
        return if multibyte_chars?(text)

        tags[range.from] = Tag.new(range:, restore_source: true)
      end

      # Record tag info for HTML comments (without ERB)
      # Comments with multi-byte characters are skipped
      # @rbs node: ::Herb::AST::HTMLCommentNode
      def record_html_comment_tag(node) #: void
        range = NodeRange.compute_char_range(node, source)
        text = source.slice(range)

        # Skip recording tag info for comments with multi-byte characters
        # to preserve character count between ruby_code and hybrid_code
        return if multibyte_chars?(text)

        tags[range.from] = Tag.new(range:, restore_source: true)
      end

      # Record tag info for AST restoration
      # @rbs node: html_node
      def record_tag(node) #: void
        range = NodeRange.compute_char_range(node, source)
        tags[range.from] = Tag.new(range:, restore_source: true)
      end

      # Check if text contains multi-byte characters
      # @rbs text: String
      def multibyte_chars?(text) #: bool
        text.bytesize != text.length
      end
    end
  end
end
