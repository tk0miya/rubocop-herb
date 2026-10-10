# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    # Visitor that collects ERB locations in a single AST traversal.
    # Also collects HTML tags when html_visualization is enabled.
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
        :erb_locations,    #: Hash[Integer, ErbLocation]
        :erb_max_columns,  #: Hash[Integer, Integer] -- line => max column (character-based, from Herb)
        :tags              #: Hash[Integer, Tag]
      )

      # Collect ERB locations and tags from a parse result
      # @rbs source: Source
      # @rbs ast: ::Herb::ParseResult
      # @rbs html_visualization: bool
      def self.collect(source, ast, html_visualization: false) #: Result
        collector = new(source:, html_visualization:)
        ast.visit(collector)

        erb_tags = collector.erb_locations.transform_values do |loc|
          Tag.new(range: loc.range, restore_source: false)
        end

        Result.new(
          erb_locations: collector.erb_locations,
          erb_max_columns: collector.erb_max_columns,
          tags: erb_tags.merge(collector.tags)
        )
      end

      attr_reader :source #: Source
      attr_reader :html_visualization #: bool
      attr_reader :erb_locations #: Hash[Integer, ErbLocation]
      attr_reader :erb_max_columns #: Hash[Integer, Integer]
      attr_reader :tags #: Hash[Integer, Tag]

      # @rbs source: Source
      # @rbs html_visualization: bool
      def initialize(source:, html_visualization:) #: void
        @erb_locations = {}
        @erb_max_columns = {}
        @tags = {}
        @source = source
        @html_visualization = html_visualization

        super()
      end

      # @rbs node: ::Herb::AST::Node
      def visit_child_nodes(node) #: void
        if erb_node?(node)
          erb = node #: erb_node
          record_erb_location(erb)
        end
        super
      end

      # Visit HTML element nodes and collect tag info when html_visualization is enabled
      # super is called first to traverse children and collect ERB locations,
      # then we check if this element contains ERB to decide which tags to record
      # @rbs node: ::Herb::AST::HTMLElementNode
      def visit_html_element_node(node) #: void
        super
        record_html_element_tag(node) if html_visualization
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
        node.class.name.not_nil!.start_with?("Herb::AST::ERB")
      end

      # Record the location of an ERB node
      # @rbs node: erb_node
      def record_erb_location(node) #: void
        type = determine_type(node)
        range = NodeRange.compute_char_range(node, source)
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

        erb_max_columns[line] = [erb_max_columns[line] || 0, column].max.not_nil!
      end

      # Determine the type of an ERB node
      # @rbs node: erb_node
      def determine_type(node) #: ErbLocation::erb_node_type
        case node
        when ::Herb::AST::ERBContentNode
          node.tag_opening.not_nil!.value == "<%=" ? :output : :content
        else
          NODE_TYPE_MAP.fetch(node.class)
        end
      end

      # Check if a node contains ERB nodes (within its byte range)
      # @rbs node: ::Herb::AST::Node
      def contains_erb?(node) #: bool
        range = NodeRange.compute_char_range(node, source)
        erb_locations.keys.any? { _1 >= range.from && _1 < range.to }
      end

      # Record tag info for HTML elements
      # For elements with ERB: record open_tag (if it doesn't contain ERB) and close_tag
      # For elements without ERB: record the whole element
      # @rbs node: ::Herb::AST::HTMLElementNode
      def record_html_element_tag(node) #: void
        if contains_erb?(node)
          # Only restore open tag if it doesn't contain ERB (e.g., ERB in attributes)
          # Restoring tags with ERB causes false positives in Layout/SpaceAroundOperators
          open_tag = node.open_tag
          record_tag(open_tag) if open_tag && !contains_erb?(open_tag)

          close_tag = node.close_tag
          record_tag(close_tag) if close_tag
        else
          record_tag(node)
        end
      end

      # Record tag info for text nodes
      # Text nodes with multi-byte characters are skipped
      # @rbs node: ::Herb::AST::HTMLTextNode
      def record_text_node_tag(node) #: void
        range = NodeRange.compute_char_range(node, source)
        text = source.slice(range)

        # Must have non-whitespace content and enough space for marker
        match = text.match(/\S/)
        return unless match

        pos = range.from + match.begin(0).not_nil!
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
      # @rbs node: ::Herb::AST::Node
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
