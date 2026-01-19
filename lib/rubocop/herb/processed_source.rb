# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Herb
    # ProcessedSource subclass that restores original HTML tag information in AST
    # After parsing Ruby code, it uses RuboCopASTTransformer visitor to replace locations
    # of HTML tag nodes with their original HTML source
    class ProcessedSource < ::RuboCop::AST::ProcessedSource
      attr_reader :hybrid_code #: String
      attr_reader :tags #: Hash[Integer, Tag]
      attr_reader :ast #: ::AST::Node?

      # @rbs ruby_code: String
      # @rbs ruby_version: Float
      # @rbs path: String?
      # @rbs hybrid_code: String
      # @rbs tags: Hash[Integer, Tag]
      # @rbs parser_engine: Symbol
      def initialize(ruby_code, ruby_version, path = nil, hybrid_code:, tags: {}, parser_engine: :default) #: void
        @hybrid_code = hybrid_code
        @tags = tags
        super(ruby_code, ruby_version, path, parser_engine:)
      end

      private

      # Override parse to transform AST after parsing
      # @rbs ruby_code: String
      # @rbs ruby_version: Float
      # @rbs parser_engine: Symbol
      # @rbs prism_result: untyped
      def parse(ruby_code, ruby_version, parser_engine, prism_result)
        super
        transform_ast if ast && tags.any?
      end

      def transform_ast #: void
        buffer.instance_variable_set(:@source, hybrid_code)
        @ast = RuboCopASTTransformer.transform(ast, tags)
      end
    end
  end
end
