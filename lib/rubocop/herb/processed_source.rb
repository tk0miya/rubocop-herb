# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Herb
    # ProcessedSource subclass that restores original HTML tag information in AST
    # After parsing Ruby code, it uses RuboCopASTTransformer visitor to replace locations
    # of HTML tag nodes with their original HTML source
    class ProcessedSource < ::RuboCop::AST::ProcessedSource
      attr_reader :source #: Source
      attr_reader :html_tags #: Hash[Integer, HtmlTag]
      attr_reader :ast #: ::AST::Node?

      # @rbs code: String
      # @rbs ruby_version: Float
      # @rbs path: String?
      # @rbs source: Source
      # @rbs html_tags: Hash[Integer, HtmlTag]
      # @rbs parser_engine: Symbol
      def initialize(code, ruby_version, path = nil, source:, html_tags: {}, parser_engine: :default) #: void
        @source = source
        @html_tags = html_tags
        super(code, ruby_version, path, parser_engine:)
      end

      private

      # Override parse to transform AST after parsing
      # @rbs code: String
      # @rbs ruby_version: Float
      # @rbs parser_engine: Symbol
      # @rbs prism_result: untyped
      def parse(code, ruby_version, parser_engine, prism_result)
        super
        transform_ast if ast && html_tags.any?
      end

      def transform_ast #: void
        @ast = RuboCopASTTransformer.transform(ast, source, html_tags)
      end
    end
  end
end
