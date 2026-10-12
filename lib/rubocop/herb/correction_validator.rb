# frozen_string_literal: true

require "herb"
require "rubocop"

module RuboCop
  module Herb
    # Validates an autocorrection made on the Ruby code converted from an ERB file.
    #
    # Cops correct the converted Ruby code, so a correction spanning multiple ERB tags may
    # move or drop the HTML and ERB delimiters between them (e.g. swapping if/else branches).
    # It may also move the code of output tags into other tags, as output tags are rendered as `_ = code`
    # (e.g. `<% unless a %><%= x %><% else %><%= y %><% end %>` into `<% _ = a ? y : x %>`),
    # which stops rendering the result of the code.
    # A correction is accepted only if applying it to the original ERB source keeps
    # the HTML parts as they are, keeps the number of output tags and does not introduce new parse errors.
    class CorrectionValidator
      ERB_TOKEN_TYPES = %w[TOKEN_ERB_START TOKEN_ERB_CONTENT TOKEN_ERB_END].freeze #: Array[String]

      attr_reader :parse_result #: ParseResult

      # @rbs @html_segments: Array[String]?
      # @rbs @output_tag_count: Integer?

      # @rbs parse_result: ParseResult
      def initialize(parse_result) #: void
        @parse_result = parse_result
      end

      # @rbs corrector: ::RuboCop::Cop::Corrector -- corrector for the converted Ruby code
      def valid?(corrector) #: bool
        corrected = apply(corrector)
        tokens = tokens_of(corrected)
        return false unless html_segments_of(tokens) == html_segments
        return false unless output_tag_count_of(tokens) == output_tag_count

        ::Herb.parse(corrected).errors.size <= parse_result.ast.errors.size
      end

      private

      # Apply the corrector to the original ERB source
      # The converted Ruby code keeps the character positions of the ERB source,
      # so the correction can be imported as is.
      # @rbs corrector: ::RuboCop::Cop::Corrector
      def apply(corrector) #: String
        buffer = ::Parser::Source::Buffer.new(parse_result.source.path, source: parse_result.code)
        erb_corrector = ::RuboCop::Cop::Corrector.new(buffer)
        erb_corrector.import!(corrector, offset: 0)
        erb_corrector.rewrite
      end

      def html_segments #: Array[String]
        @html_segments ||= html_segments_of(tokens_of(parse_result.code))
      end

      def output_tag_count #: Integer
        @output_tag_count ||= output_tag_count_of(tokens_of(parse_result.code))
      end

      # @rbs code: String
      def tokens_of(code) #: Array[::Herb::Token]
        ::Herb.lex(code).value.__getobj__
      end

      # Split the source into the HTML parts between ERB tags
      # Leading and trailing whitespace of each part is ignored as it is the layout of
      # the adjacent ERB tags.  This allows corrections removing ERB tags (e.g. merging
      # `else` and `if` into `elsif`) along with their indentation and newlines.
      # @rbs tokens: Array[::Herb::Token]
      def html_segments_of(tokens) #: Array[String]
        # ERB tokens are dropped as separators, so each chunk is an HTML part
        chunks = tokens.chunk { erb_token?(_1) ? :_separator : :html }
        chunks.map { _1.last.map(&:value).join.strip }.reject(&:empty?)
      end

      # The number of output tags (`<%=` and `<%==`)
      # @rbs tokens: Array[::Herb::Token]
      def output_tag_count_of(tokens) #: Integer
        tokens.count { _1.type == "TOKEN_ERB_START" && ErbLocation::OUTPUT_TAG_OPENINGS.include?(_1.value) }
      end

      # @rbs token: ::Herb::Token
      def erb_token?(token) #: bool
        ERB_TOKEN_TYPES.include?(token.type)
      end
    end
  end
end
