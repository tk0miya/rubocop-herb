# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Herb
    # Custom ProcessedSource that replaces AST node sources for HTML tags
    class HtmlAwareProcessedSource < ::RuboCop::ProcessedSource
      attr_reader :html_tag_mappings #: Array[{from: Integer, to: Integer, original: String}]

      # @rbs code: String
      # @rbs ruby_version: Float
      # @rbs path: String?
      # @rbs html_tag_mappings: Array[{from: Integer, to: Integer, original: String}]
      # @rbs parser_engine: Symbol
      def initialize(code, ruby_version, path = nil, html_tag_mappings: [], parser_engine: :parser_prism)
        @html_tag_mappings = html_tag_mappings
        super(code, ruby_version, path, parser_engine:)
        replace_ast_with_html_sources if ast && !html_tag_mappings.empty?
      end

      private

      def replace_ast_with_html_sources #: void
        @ast = rebuild_ast(ast)
      end

      # Recursively rebuild AST, replacing HTML tag nodes with nodes that have HTML source
      # @rbs node: untyped
      def rebuild_ast(node) #: untyped
        return node unless node.is_a?(::Parser::AST::Node)

        # First, rebuild all children
        new_children = node.children.map { |child| rebuild_ast(child) }

        # Check if this node should have its source replaced
        mapping = find_mapping_for_node(node)
        if mapping
          # Create a new node with HTML source
          create_html_source_node(node, new_children, mapping[:original])
        elsif children_changed?(node.children, new_children)
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
      def create_html_source_node(node, children, html_source) #: ::Parser::AST::Node
        # Create a buffer with the HTML source
        html_buffer = ::Parser::Source::Buffer.new("(html_tag)")
        html_buffer.source = html_source

        # Create a range spanning the entire HTML
        html_range = ::Parser::Source::Range.new(html_buffer, 0, html_source.bytesize)

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
    end
  end
end
