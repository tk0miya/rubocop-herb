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
    # A correction may also remove the closing delimiter of an ERB tag rendered as whitespace
    # (e.g. at the end of an ERB comment rendered as a Ruby comment), so that the tag swallows the following tags,
    # or remove `#` of `<%#`, so that the text of an ERB comment becomes code.
    # The conversion renders a semicolon in the whitespace before the closing delimiter of an ERB tag
    # (`<%= x  %>` becomes `_ = x;   `), so a correction breaking a line after it (e.g. Layout/LineLength)
    # moves the closing delimiter to the next line instead of shortening the line.
    # A correction is accepted only if applying it to the original ERB source keeps
    # the HTML parts as they are, keeps the number of output tags, does not make ERB tags swallow other tags,
    # does not increase the number of ERB tags with code, does not introduce new parse errors
    # and does not move closing delimiters to the next line.
    class CorrectionValidator
      ERB_TOKEN_TYPES = %w[TOKEN_ERB_START TOKEN_ERB_CONTENT TOKEN_ERB_END].freeze #: Array[String]

      attr_reader :parse_result #: ParseResult

      # @rbs @html_segments: Array[String]?
      # @rbs @output_tag_count: Integer?
      # @rbs @swallowed_tag_count: Integer?
      # @rbs @code_tag_count: Integer?

      # @rbs parse_result: ParseResult
      def initialize(parse_result) #: void
        @parse_result = parse_result
      end

      # @rbs corrector: ::RuboCop::Cop::Corrector -- corrector for the converted Ruby code
      def valid?(corrector) #: bool
        return false if breaks_before_closing_delimiter?(corrector)

        corrected = apply(corrector)
        return false unless keeps_structure?(tokens_of(corrected))

        ::Herb.parse(corrected).errors.size <= parse_result.ast.errors.size
      end

      private

      # Whether the tokens of the corrected source keep the HTML parts and the output tags,
      # do not have ERB tags swallowing other tags and do not have more ERB tags with code
      # @rbs tokens: Array[::Herb::Token]
      def keeps_structure?(tokens) #: bool
        html_segments_of(tokens) == html_segments &&
          output_tag_count_of(tokens) == output_tag_count &&
          swallowed_tag_count_of(tokens) <= swallowed_tag_count &&
          code_tag_count_of(tokens) <= code_tag_count
      end

      # Whether the corrector inserts a line break between the code and the closing delimiter of an ERB tag
      # on the same line, which moves the delimiter to the next line
      # @rbs corrector: ::RuboCop::Cop::Corrector
      def breaks_before_closing_delimiter?(corrector) #: bool
        corrector.as_replacements.any? do |range, text|
          text.include?("\n") && before_closing_delimiter?(range.begin_pos, range.end_pos)
        end
      end

      # Whether the range is in the whitespace between the code and the closing delimiter of an ERB tag
      # (including the end of the code), without line breaks
      # An unclosed ERB tag has no closing delimiter to move
      # @rbs from: Integer
      # @rbs to: Integer
      def before_closing_delimiter?(from, to) #: bool
        tag = parse_result.erb_tag_ranges.bsearch { _1.to > from }
        return false unless tag && tag.from <= from

        match = parse_result.slice(tag).match(/([ \t]*)(-?%>)\z/)
        return false unless match

        delimiter_from = tag.to - match[2].to_s.length
        delimiter_from - match[1].to_s.length <= from && to <= delimiter_from
      end

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

      def swallowed_tag_count #: Integer
        @swallowed_tag_count ||= swallowed_tag_count_of(tokens_of(parse_result.code))
      end

      def code_tag_count #: Integer
        @code_tag_count ||= code_tag_count_of(tokens_of(parse_result.code))
      end

      # The number of ERB tags except comments (`<%#`), which ERB comments turn into if `#` is removed
      # @rbs tokens: Array[::Herb::Token]
      def code_tag_count_of(tokens) #: Integer
        tokens.count { _1.type == "TOKEN_ERB_START" && !_1.value.match?(/\A<%-?#/) }
      end

      # The number of tag openings (`<%`) in the contents of ERB tags, which are swallowed tags
      # (or `<%` written in the code, e.g. in a string)
      # @rbs tokens: Array[::Herb::Token]
      def swallowed_tag_count_of(tokens) #: Integer
        tokens.sum { _1.type == "TOKEN_ERB_CONTENT" ? _1.value.scan("<%").size : 0 }
      end

      # @rbs code: String
      def tokens_of(code) #: Array[::Herb::Token]
        ::Herb.lex(code).value.__getobj__
      end

      # Split the source into the HTML parts between ERB tags
      # Leading and trailing whitespace of each part is ignored as it is the layout of
      # the adjacent ERB tags.  This allows corrections removing ERB tags (e.g. merging
      # `else` and `if` into `elsif`) along with their indentation and newlines.
      # Escaped ERB tags (e.g. `<%% x %>`) are text, so they are kept as HTML.
      # @rbs tokens: Array[::Herb::Token]
      def html_segments_of(tokens) #: Array[String]
        # ERB tokens are dropped as separators, so each chunk is an HTML part
        escaped = false
        chunks = tokens.chunk do |token|
          escaped = token.value.start_with?(ErbNode::ESCAPED_TAG_OPENING) if token.type == "TOKEN_ERB_START"
          erb_token?(token) && !escaped ? :_separator : :html
        end
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
