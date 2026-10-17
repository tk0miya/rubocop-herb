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
      # @rbs @correction_validator: CorrectionValidator?
      # @rbs @correction_adjuster: CorrectionAdjuster?

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
        transform_ast if ast && parse_result.tags.any?
      end

      def transform_ast #: void
        return unless ast

        replace_buffer_source(hybrid_code)
        @ast = RuboCopASTTransformer.transform(ast, parse_result)
      end

      # Replace the source of the buffer, which is immutable once populated.
      # The buffer also keeps a UTF-32 copy of non-ASCII source to slice it (`@slice_source`),
      # so it is cleared and repopulated in the same way as RuboCop populates the buffer.
      # @rbs source: String
      def replace_buffer_source(source) #: void
        buffer.instance_variable_set(:@source, nil)
        buffer.instance_variable_set(:@slice_source, nil)
        buffer.source = source
      end
    end
  end
end
