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
      # the lines of expressions that cannot be moved out of conditionals,
      # the lines of trailing whitespace rendered by the conversion and the lines without ERB tags (for line length)
      def comment_config #: CommentConfig
        @comment_config ||= CommentConfig.new(self, disabled_cops:)
      end

      # Validator to discard autocorrections that would break the ERB template
      def correction_validator #: CorrectionValidator
        @correction_validator ||= CorrectionValidator.new(parse_result)
      end

      # Adjuster to trim autocorrections to the content of ERB tags
      # The raw source is normalized as the buffer is (CRLF to LF), on which the positions of corrections are based
      def correction_adjuster #: CorrectionAdjuster
        @correction_adjuster ||= CorrectionAdjuster.new(parse_result, raw_source.gsub("\r\n", "\n"))
      end

      private

      def disabled_cops #: Hash[String, Array[Range[Integer]]]
        immovable_expressions = ImmovableExpressionCollector.collect(self, parse_result)
        rendered_trailing_whitespace = TrailingWhitespaceCollector.collect(self, parse_result)
        html_only_lines = LineLengthCollector.collect(self, parse_result)
        [immovable_expressions, rendered_trailing_whitespace, html_only_lines]
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
        @ast = RuboCopASTTransformer.transform(ast, parse_result) if ast
      end
    end
  end
end
