# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Herb
    # ProcessedSource subclass that transforms AST after parsing with RuboCopASTTransformer
    # to make nodes rendered from HTML unique
    class ProcessedSource < ::RuboCop::AST::ProcessedSource
      attr_reader :parse_result #: ParseResult
      attr_reader :ast #: RuboCop::AST::Node?

      # @rbs @comment_config: CommentConfig?
      # @rbs @correction_validator: CorrectionValidator?
      # @rbs @correction_adjuster: CorrectionAdjuster?
      # @rbs @verbatim_code: VerbatimCode?

      # @rbs ruby_code: String
      # @rbs ruby_version: Float
      # @rbs path: String?
      # @rbs parse_result: ParseResult
      # @rbs parser_engine: Symbol
      def initialize(ruby_code, ruby_version, path = nil,
                     parse_result:, parser_engine: :default) #: void
        @parse_result = parse_result
        super(ruby_code, ruby_version, path, parser_engine:)
      end

      # Override comment_config to disable cops at the lines specified by the parse result,
      # the lines of expressions that cannot be moved out of conditionals
      # and the lines without ERB tags (for line length)
      def comment_config #: CommentConfig
        @comment_config ||= CommentConfig.new(self, disabled_cops:)
      end

      # The node of the AST before the transformation at the same place as the given node of the transformed AST
      # (e.g. `(send nil :div)` for `(send nil :div__html0)`), or nil if the node is not in the transformed AST.
      # The node is found by its type and its range, as the transformation keeps them.
      # This is for the scopes of ReparsedEquivalence (the root node, method definitions, classes and modules),
      # no two of which have the same type and range.
      # @rbs node: RuboCop::AST::Node
      def untransformed_node(node) #: RuboCop::AST::Node?
        return untransformed_ast if node.equal?(ast)
        return nil unless node.each_ancestor.any? { _1.equal?(ast) }

        range = node.source_range
        untransformed_ast&.each_node(node.type)&.find { _1.source_range == range }
      end

      # Validator to discard autocorrections that would break the ERB template
      def correction_validator #: CorrectionValidator
        @correction_validator ||= CorrectionValidator.new(parse_result)
      end

      # Checker for the code copied verbatim from ERB tags
      def verbatim_code #: VerbatimCode
        @verbatim_code ||= VerbatimCode.new(parse_result)
      end

      # Adjuster to trim autocorrections to the content of ERB tags
      # The raw source is normalized as the buffer is (CRLF to LF), on which the positions of corrections are based
      def correction_adjuster #: CorrectionAdjuster
        @correction_adjuster ||= CorrectionAdjuster.new(parse_result, raw_source.gsub("\r\n", "\n"))
      end

      private

      attr_reader :untransformed_ast #: RuboCop::AST::Node?

      def disabled_cops #: Hash[String, Array[Range[Integer]]]
        immovable_expressions = ImmovableExpressionCollector.collect(self, parse_result)
        html_only_lines = HtmlOnlyLineCollector.collect(self, parse_result)
        [immovable_expressions, html_only_lines]
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
        @untransformed_ast = ast
        @ast = RuboCopASTTransformer.transform(ast, parse_result) if ast
      end
    end
  end
end
