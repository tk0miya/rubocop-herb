# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Herb
    # Custom Range that uses the original buffer but returns HTML source
    # This satisfies RuboCop's corrector buffer validation while showing HTML in messages
    class HtmlSourceRange < ::Parser::Source::Range
      # @rbs buffer: ::Parser::Source::Buffer
      # @rbs begin_pos: Integer
      # @rbs end_pos: Integer
      # @rbs html_source: String
      def initialize(buffer, begin_pos, end_pos, html_source) # rubocop:disable Lint/MissingSuper
        @html_source = html_source
        # Manually set instance variables to avoid frozen object issues
        @source_buffer = buffer
        @begin_pos = begin_pos
        @end_pos = end_pos
        freeze
      end

      def source #: String
        @html_source
      end
    end

    # Custom ProcessedSource that replaces AST node sources for HTML tags
    class HtmlAwareProcessedSource < ::RuboCop::ProcessedSource # rubocop:disable Metrics/ClassLength
      attr_reader :html_tag_mappings #: Array[{from: Integer, to: Integer, original: String, html_end: Integer}]
      attr_reader :erb_end_mappings #: Array[{from: Integer, to: Integer, erb_end: Integer}]

      # @rbs code: String
      # @rbs ruby_version: Float
      # @rbs path: String?
      # @rbs html_tag_mappings: Array[{from: Integer, to: Integer, original: String, html_end: Integer}]
      # @rbs erb_end_mappings: Array[{from: Integer, to: Integer, erb_end: Integer}]
      # @rbs parser_engine: Symbol
      def initialize(code, ruby_version, path = nil, **options)
        @html_tag_mappings = options[:html_tag_mappings] || []
        @erb_end_mappings = options[:erb_end_mappings] || []
        super(code, ruby_version, path, parser_engine: options[:parser_engine] || :parser_prism)
        rebuild_ast_if_needed
      end

      private

      def rebuild_ast_if_needed #: void
        return unless ast
        return if html_tag_mappings.empty? && erb_end_mappings.empty?

        @ast = rebuild_ast(ast)
      end

      # Recursively rebuild AST, replacing HTML tag nodes with nodes that have HTML source
      # @rbs node: untyped
      def rebuild_ast(node) #: untyped
        return node unless node.is_a?(::Parser::AST::Node)

        # First, rebuild all children
        new_children = node.children.map { |child| rebuild_ast(child) }

        # Check if this node should have its source replaced (HTML tags)
        html_mapping = find_mapping_for_node(node)
        if html_mapping
          return create_html_source_node(node, new_children, html_mapping[:original], html_mapping[:html_end])
        end

        # Check if this is a control flow node that needs its end extended
        erb_end_mapping = find_erb_end_mapping_for_node(node)
        return extend_node_end(node, new_children, erb_end_mapping[:erb_end]) if erb_end_mapping

        if children_changed?(node.children, new_children)
          # Children changed, create new node
          node.updated(nil, new_children)
        else
          # No changes needed
          node
        end
      end

      # Compare children by object identity, not value equality
      # (AST nodes compare equal if they have same type/children, ignoring location)
      # @rbs original: Array[untyped]
      # @rbs updated: Array[untyped]
      def children_changed?(original, updated) #: bool
        return true if original.length != updated.length

        original.zip(updated).any? { |a, b| !a.equal?(b) }
      end

      # @rbs node: ::Parser::AST::Node
      def find_mapping_for_node(node) #: Hash[Symbol, untyped]?
        return nil unless node.loc&.expression

        node_start = node.loc.expression.begin_pos
        node_end = node.loc.expression.end_pos

        html_tag_mappings.find do |mapping|
          mapping[:from] == node_start && mapping[:to] == node_end
        end
      end

      # @rbs node: ::Parser::AST::Node
      # @rbs children: Array[untyped]
      # @rbs html_source: String
      # @rbs html_end: Integer
      def create_html_source_node(node, children, html_source, html_end) #: ::Parser::AST::Node
        # Create a custom range that uses original buffer but returns HTML source
        # Use html_end (original HTML tag end position) for proper autocorrect positioning
        original_range = node.loc.expression
        html_range = HtmlSourceRange.new(
          original_range.source_buffer,
          original_range.begin_pos,
          html_end,
          html_source
        )

        # Create appropriate map based on node type
        new_map = create_source_map_for_node(node, html_range)

        # Create new node with HTML source location
        node.updated(nil, children, { location: new_map })
      end

      # @rbs node: ::Parser::AST::Node
      # @rbs html_range: ::Parser::Source::Range
      def create_source_map_for_node(node, html_range) #: ::Parser::Source::Map
        case node.loc
        when ::Parser::Source::Map::Send
          ::Parser::Source::Map::Send.new(nil, html_range, nil, nil, html_range)
        else
          ::Parser::Source::Map.new(html_range)
        end
      end

      # Check if this is a control flow node whose end keyword falls within an ERB end tag
      # @rbs node: ::Parser::AST::Node
      def find_erb_end_mapping_for_node(node) #: Hash[Symbol, untyped]?
        return nil unless control_flow_node?(node)
        return nil unless node.loc.respond_to?(:end) && node.loc.end

        end_keyword_start = node.loc.end.begin_pos
        end_keyword_end = node.loc.end.end_pos

        erb_end_mappings.find do |mapping|
          mapping[:from] == end_keyword_start && mapping[:to] == end_keyword_end
        end
      end

      # @rbs node: ::Parser::AST::Node
      def control_flow_node?(node) #: bool
        %i[if unless case while until for begin].include?(node.type)
      end

      # Extend the node's location to cover the full ERB end tag
      # @rbs node: ::Parser::AST::Node
      # @rbs children: Array[untyped]
      # @rbs erb_end: Integer
      def extend_node_end(node, children, erb_end) #: ::Parser::AST::Node
        original_range = node.loc.expression
        extended_range = ::Parser::Source::Range.new(
          original_range.source_buffer,
          original_range.begin_pos,
          erb_end
        )

        # Create new location map with extended expression range
        new_map = extend_location_map(node.loc, extended_range, erb_end)

        node.updated(nil, children, { location: new_map })
      end

      # @rbs loc: ::Parser::Source::Map
      # @rbs extended_range: ::Parser::Source::Range
      # @rbs erb_end: Integer
      def extend_location_map(loc, extended_range, erb_end) #: ::Parser::Source::Map # rubocop:disable Metrics/AbcSize
        case loc
        when ::Parser::Source::Map::Condition
          # For if/unless/case nodes
          extended_end = extend_end_range(loc.end, erb_end) if loc.end
          ::Parser::Source::Map::Condition.new(
            loc.keyword,
            loc.begin,
            loc.else,
            extended_end,
            extended_range
          )
        when ::Parser::Source::Map::For
          # For for loops
          extended_end = extend_end_range(loc.end, erb_end) if loc.end
          ::Parser::Source::Map::For.new(
            loc.keyword,
            loc.in,
            loc.begin,
            extended_end,
            extended_range
          )
        when ::Parser::Source::Map::Keyword
          # For while/until/begin
          extended_end = extend_end_range(loc.end, erb_end) if loc.end
          ::Parser::Source::Map::Keyword.new(
            loc.keyword,
            loc.begin,
            extended_end,
            extended_range
          )
        else
          ::Parser::Source::Map.new(extended_range)
        end
      end

      # @rbs end_range: ::Parser::Source::Range?
      # @rbs erb_end: Integer
      def extend_end_range(end_range, erb_end) #: ::Parser::Source::Range?
        return nil unless end_range

        ::Parser::Source::Range.new(
          end_range.source_buffer,
          end_range.begin_pos,
          erb_end
        )
      end
    end
  end
end
