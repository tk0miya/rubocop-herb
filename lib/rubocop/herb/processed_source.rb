# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Herb
    # ProcessedSource subclass that transforms AST after parsing with RuboCopASTTransformer
    # to make the nodes of HTML unique
    #
    # HTML gets its nodes here: the code in which the markers of HTML are inserted (see ExpandedCode) is parsed
    # instead of the Ruby code, and the positions in the result are converted back to the ones in the Ruby code
    # (see LocationRemapper).
    # The buffer is still the Ruby code, which has only the code in ERB tags, so the AST is not the one of parsing
    # the buffer when the source has HTML. The cops parsing the buffer again get the AST of the buffer with
    # untransformed_node.
    class ProcessedSource < ::RuboCop::AST::ProcessedSource
      attr_reader :parse_result #: ParseResult
      attr_reader :html_markers #: Array[HtmlMarker]
      attr_reader :ast #: RuboCop::AST::Node?

      # @rbs @comment_config: CommentConfig?
      # @rbs @correction_validator: CorrectionValidator?
      # @rbs @correction_adjuster: CorrectionAdjuster?
      # @rbs @verbatim_code: VerbatimCode?
      # @rbs @buffer_ast: RuboCop::AST::Node?
      # @rbs @buffer: ::Parser::Source::Buffer

      # @rbs!
      #   def diagnostics: () -> Array[::Parser::Diagnostic]

      # @rbs ruby_code: String
      # @rbs ruby_version: Float
      # @rbs path: String?
      # @rbs parse_result: ParseResult
      # @rbs html_markers: Array[HtmlMarker]
      # @rbs parser_engine: Symbol
      def initialize(ruby_code, ruby_version, path = nil,
                     parse_result:, html_markers: [], parser_engine: :default) #: void
        @parse_result = parse_result
        @html_markers = html_markers
        super(ruby_code, ruby_version, path, parser_engine:)
      end

      # Override comment_config to disable cops at the lines specified by the parse result,
      # the lines of expressions that cannot be moved out of conditionals
      # and the lines without ERB tags (for line length)
      def comment_config #: CommentConfig
        @comment_config ||= CommentConfig.new(self, disabled_cops:)
      end

      # The node of the AST of the buffer at the same place as the given node of the AST,
      # or nil if the buffer has no such node. The AST of the buffer has no nodes of HTML.
      # The node is found by its type and its range, as the nodes of HTML change the structure of the AST.
      # This is for the scopes of ReparsedEquivalence (the root node, method definitions, classes and modules),
      # whose ranges do not change with the nodes of HTML, except the root node.
      # @rbs node: RuboCop::AST::Node
      def untransformed_node(node) #: RuboCop::AST::Node?
        return buffer_ast if node.equal?(ast)
        return nil unless node.each_ancestor.any? { _1.equal?(ast) }

        # The ranges of the two ASTs belong to different buffers and never equal, so the positions are compared
        range = node.source_range
        buffer_ast&.each_node(node.type)&.find do |candidate|
          candidate_range = candidate.source_range
          candidate_range.begin_pos == range.begin_pos && candidate_range.end_pos == range.end_pos
        end
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
        @correction_adjuster ||= CorrectionAdjuster.new(parse_result, raw_source.gsub("\r\n", "\n"), html_markers)
      end

      private

      attr_reader :untransformed_ast #: RuboCop::AST::Node?

      # The AST of the buffer: the AST before the transformation, or the one of parsing the buffer again
      # if the source has HTML markers, as their nodes are not in the buffer
      def buffer_ast #: RuboCop::AST::Node?
        return untransformed_ast if html_markers.empty?

        @buffer_ast ||= ::RuboCop::AST::ProcessedSource.new(raw_source, ruby_version, path, parser_engine:).ast
      end

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

      # Override tokenize to parse the code in which the markers of HTML are inserted,
      # and to move the result onto the buffer
      # @rbs parser: untyped
      def tokenize(parser) #: [RuboCop::AST::Node?, Array[::Parser::Source::Comment], untyped]
        return super if html_markers.empty?

        source_buffer = buffer
        expanded_code = ExpandedCode.new(source_buffer.source, html_markers)
        @buffer = ::Parser::Source::Buffer.new(source_buffer.name, 1, source: expanded_code.code)
        ast, comments, tokens = super
        @buffer = source_buffer

        remapper = LocationRemapper.new(source_buffer, expanded_code)
        diagnostics.map! { remapper.remap_diagnostic(_1) }
        [remap_ast(ast, remapper), remapper.remap_comments(comments), remap_tokens(tokens, remapper)]
      end

      # @rbs ast: RuboCop::AST::Node?
      # @rbs remapper: LocationRemapper
      def remap_ast(ast, remapper) #: RuboCop::AST::Node?
        return nil unless ast

        remapped = remapper.remap_node(ast) #: untyped
        remapped.complete! # as RuboCop::AST::ProcessedSource#tokenize does
        remapped
      end

      # The tokens of the prism engine are built lazily (a Proc), so they are remapped when they are built
      # @rbs tokens: untyped
      # @rbs remapper: LocationRemapper
      def remap_tokens(tokens, remapper) #: untyped
        return -> { remapper.remap_tokens(tokens.call) } if tokens.is_a?(Proc)

        remapper.remap_tokens(tokens)
      end
    end
  end
end
