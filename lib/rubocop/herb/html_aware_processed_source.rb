# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Herb
    # Custom ProcessedSource that stores HTML tag mappings for source replacement
    # Note: AST nodes are frozen by parser, so we can't modify them directly.
    # Instead, we store the mappings and provide lookup methods.
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
      end

      # Find the original HTML source for a given AST node position
      # @rbs node: ::RuboCop::AST::Node
      def original_html_for(node) #: String?
        return nil unless node.respond_to?(:loc) && node.loc&.expression

        node_start = node.loc.expression.begin_pos
        node_end = node.loc.expression.end_pos

        mapping = html_tag_mappings.find do |m|
          m[:from] == node_start && m[:to] == node_end
        end

        mapping&.dig(:original)
      end

      # Check if a node represents an HTML tag
      # @rbs node: ::RuboCop::AST::Node
      def html_tag_node?(node) #: bool
        !original_html_for(node).nil?
      end
    end
  end
end
