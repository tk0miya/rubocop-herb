# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Herb
    # ProcessedSource subclass that restores original HTML tag information in AST
    # After parsing Ruby code, it uses RuboCopASTTransformer visitor to replace locations
    # of HTML tag nodes with their original HTML source
    class ProcessedSource < ::RuboCop::AST::ProcessedSource
      attr_reader :hybrid_code #: String
      attr_reader :parse_result #: ParseResult
      attr_reader :ast #: RuboCop::AST::Node?

      # @rbs @comment_config: CommentConfig?

      # @rbs ruby_code: String
      # @rbs ruby_version: Float
      # @rbs path: String?
      # @rbs hybrid_code: String
      # @rbs parse_result: ParseResult
      # @rbs parser_engine: Symbol
      def initialize(ruby_code, ruby_version, path = nil,
                     hybrid_code:, parse_result:, parser_engine: :default) #: void
        @hybrid_code = hybrid_code
        @parse_result = parse_result
        super(ruby_code, ruby_version, path, parser_engine:)
      end

      # Override comment_config to disable cops at the lines specified by the parse result,
      # the lines of expressions that cannot be moved out of conditionals
      # and the lines of trailing whitespace rendered by the conversion
      def comment_config #: CommentConfig
        @comment_config ||= CommentConfig.new(self, disabled_cops:)
      end

      private

      def disabled_cops #: Hash[String, Array[Range[Integer]]]
        immovable_expressions = ImmovableExpressionCollector.collect(self, parse_result)
        rendered_trailing_whitespace = TrailingWhitespaceCollector.collect(self, parse_result)
        [immovable_expressions, rendered_trailing_whitespace]
          .reduce(parse_result.disabled_cops) do |disabled_cops, lines|
          disabled_cops.merge(lines) { |_cop, lines1, lines2| lines1 + lines2 }
        end
      end

      # Override parse to transform AST after parsing
      # @rbs ruby_code: String
      # @rbs ruby_version: Float
      # @rbs parser_engine: Symbol
      # @rbs prism_result: untyped
      def parse(ruby_code, ruby_version, parser_engine, prism_result) #: void
        super
        transform_ast if ast && parse_result.tags.any?
      end

      def transform_ast #: void
        return unless ast

        buffer.instance_variable_set(:@source, hybrid_code)
        @ast = RuboCopASTTransformer.transform(ast, parse_result)
      end
    end
  end
end
