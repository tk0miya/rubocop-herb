# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Herb
    # Adjusts autocorrections made on the Ruby code converted from an ERB file.
    #
    # The ERB delimiters are rendered as whitespace in the converted Ruby code, so a correction
    # removing an expression along with the whitespace around it (e.g. `Lint/Void`) also removes
    # the delimiters of its ERB tag.  The adjuster trims a replacement starting (or ending)
    # outside ERB tags to the content of the ERB tag it ends (or starts) in, if the trimmed part
    # is whitespace in the Ruby code (#trim), so that the correction keeps the delimiters.
    #
    # An ERB comment rendered as a Ruby comment continues over its closing delimiter rendered as whitespace,
    # so the corrections of rubocop directives in it (e.g. Lint/RedundantCopDisableDirective) are also adjusted
    # to keep the delimiters (`<%#` and `%>`) of the comment, or to remove the whole ERB tag.
    class CorrectionAdjuster
      # The content of an ERB tag and its character range
      Content = Data.define(
        :location,  #: ErbLocation
        :range      #: CharRange
      )

      # A replacement of the correction in character positions
      Replacement = Data.define(
        :from,  #: Integer
        :to,    #: Integer
        :text   #: String
      )

      attr_reader :parse_result #: ParseResult
      attr_reader :ruby_code #: String

      # @rbs @contents: Array[Content]?
      # @rbs @comment_contents: Array[CharRange]?

      # @rbs parse_result: ParseResult
      # @rbs ruby_code: String -- Ruby code converted from the ERB source
      def initialize(parse_result, ruby_code) #: void
        @parse_result = parse_result
        @ruby_code = ruby_code
      end

      # Returns the trimmed correction, or nil if there is nothing to trim
      # @rbs corrector: ::RuboCop::Cop::Corrector -- corrector for the converted Ruby code
      def trim(corrector) #: ::RuboCop::Cop::Corrector?
        original = replacements_of(corrector)
        trimmed = original.map { trim_replacement(_1) }
        return if trimmed == original

        build_corrector(corrector.source_buffer, trimmed)
      end

      private

      # @rbs corrector: ::RuboCop::Cop::Corrector
      def replacements_of(corrector) #: Array[Replacement]
        corrector.as_replacements.map do |range, text|
          Replacement.new(from: range.begin_pos, to: range.end_pos, text:)
        end
      end

      # Contents of the ERB tags except comments, sorted by position
      def contents #: Array[Content]
        @contents ||= parse_result.erb_locations.values.filter_map { content_of(_1) }.sort_by { _1.range.from }
      end

      # @rbs location: ErbLocation
      def content_of(location) #: Content?
        return if location.comment?

        node = location.node #: erb_node
        content = node.content
        Content.new(location:, range: NodeRange.byte_range_to_char_range(content.range, parse_result.source)) if content
      end

      # Contents of the ERB comments rendered as Ruby comments
      # The ones followed by ERB tags or HTML on the same line are rendered as whitespace, so they are not adjusted
      def comment_contents #: Array[CharRange]
        @comment_contents ||= parse_result.erb_comment_nodes.filter_map do |node|
          next if parse_result.followed_by_content?(node)

          NodeRange.byte_range_to_char_range(node.content.not_nil!.range, parse_result.source)
        end
      end

      # The ERB tag of the content of an ERB comment
      # @rbs content: CharRange
      def erb_tag_of(content) #: CharRange
        parse_result.erb_tag_ranges.bsearch { _1.to >= content.to }.not_nil!
      end

      # The content in which a replacement starting at the position starts
      # A replacement starting at the end of a content starts outside it
      # @rbs pos: Integer
      def content_starting_at(pos) #: Content?
        content = contents.bsearch { _1.range.to > pos }
        content if content && content.range.from <= pos
      end

      # The content in which a replacement ending at the position ends
      # A replacement ending at the start of a content ends outside it
      # @rbs pos: Integer
      def content_ending_at(pos) #: Content?
        content = contents.bsearch { _1.range.to >= pos }
        content if content && content.range.from < pos
      end

      # Trim the replacement to the content of the ERB tag if it starts (or ends) outside ERB tags,
      # the trimmed part is whitespace in the Ruby code (e.g. the delimiters and the indentation),
      # and the part left in the content has code
      # A replacement of whitespace only (e.g. re-indenting the tag) is not trimmed, as the trimmed
      # replacement would change the whitespace inside the tag instead
      # @rbs replacement: Replacement
      def trim_replacement(replacement) #: Replacement
        comment_removal = trim_comment_removal(replacement)
        return comment_removal if comment_removal

        comment_edit = keep_comment_opening(trim_comment_edit(replacement) || replacement)
        return comment_edit unless comment_edit == replacement

        from_content = content_starting_at(replacement.from)
        to_content = content_ending_at(replacement.to)
        return replacement if from_content.nil? == to_content.nil?

        if to_content
          trim_to(replacement, from: to_content.range.from)
        else
          trim_to(replacement, to: from_content.not_nil!.range.to)
        end
      end

      # Turn the replacement of a whole ERB comment rendered as a Ruby comment, along with the whitespace around it,
      # into the removal of the ERB tag (see #comment_tag_removal).
      # Lint/RedundantCopDisableDirective removes an unnecessary directive along with the whitespace around it,
      # which also covers the delimiters of the adjacent ERB tags and the HTML rendered as whitespace.
      # It replaces the directive with ` # ` instead if the comment has more text, which the closing delimiter
      # rendered as whitespace looks like
      # @rbs replacement: Replacement
      def trim_comment_removal(replacement) #: Replacement?
        content = comment_content_replaced(replacement)
        return unless content

        removal = comment_tag_removal(erb_tag_of(content))
        replacement.with(from: removal.from, to: removal.to, text: "")
      end

      # The range to remove the ERB tag of a comment, decided from the ERB source:
      # the whole line if the line has only the tag (and whitespace), the tag with the whitespace after it
      # if the tag starts the line (keeping the indentation), or the tag with the whitespace before it
      # @rbs tag: CharRange
      def comment_tag_removal(tag) #: CharRange
        line = line_of(tag)
        before, after = surroundings(tag, line)
        return line if blank?(before) && blank?(after)
        return CharRange.new(tag.from, tag.to + after[/\A[ \t]*/].to_s.length) if blank?(before)

        CharRange.new(tag.from - before[/[ \t]*\z/].to_s.length, tag.to)
      end

      # The text before and after the tag in the line
      # @rbs tag: CharRange
      # @rbs line: CharRange
      def surroundings(tag, line) #: [String, String]
        [parse_result.slice(CharRange.new(line.from, tag.from)), parse_result.slice(CharRange.new(tag.to, line.to))]
      end

      # @rbs text: String
      def blank?(text) #: bool
        text.match?(/\A[ \t]*\n?\z/)
      end

      # The range of the line of the ERB source with the tag (with the newline)
      # @rbs tag: CharRange
      def line_of(tag) #: CharRange
        code = parse_result.code
        line_end = code.index("\n", tag.to)
        CharRange.new((code[0...tag.from].to_s.rindex("\n") || -1) + 1, line_end ? line_end + 1 : code.length)
      end

      # The content of the ERB comment replaced as a whole along with whitespace, with whitespace or `#`
      # @rbs replacement: Replacement
      def comment_content_replaced(replacement) #: CharRange?
        return unless ["", "#"].include?(replacement.text.strip)

        content = comment_contents.find { replacement.from < _1.from && _1.to <= replacement.to }
        content if content && whitespace?(replacement.from, content.from - 1) && whitespace?(content.to, replacement.to)
      end

      # Trim the replacement starting in an ERB comment rendered as a Ruby comment and running to the end of the line
      # (e.g. Lint/RedundantCopDisableDirective removing one of the cops in a directive with the whitespace after it)
      # to the end of the comment (before the whitespace at its end), as the Ruby comment continues over
      # the closing delimiter rendered as whitespace.
      # The replacement starts at `#` of `<%#` at the earliest; a removal of the whole tag starts before it
      # @rbs replacement: Replacement
      def trim_comment_edit(replacement) #: Replacement?
        content = comment_content_edited_to_end(replacement)
        return unless content && whitespace?(content.to, replacement.to)

        # The text of a replacement (e.g. Style/DirectiveScope rewriting the directive) keeps the whitespace
        # at the end of the comment, which is kept by the trimmed range
        content_end = content.from + ruby_code[content.from...content.to].to_s.rstrip.length
        replacement.with(to: [content_end, replacement.from].max, text: replacement.text.rstrip)
      end

      # Keep `#` of `<%#` of an ERB comment rendered as a Ruby comment in a replacement covering it,
      # unless the replacement covers the whole ERB tag. The replacement starts after `#` and drops `#` at the start
      # of its text, which may also start with the whitespace before the comment rendered from the delimiters
      # and the HTML before it (e.g. Lint/RedundantCopDisableDirective replacing a directive followed by more text
      # in the comment with ` # `, and removing a directive on the first line of a multi-line comment).
      # Otherwise the comment would become a code tag or a part of the ERB tag before it
      # @rbs replacement: Replacement
      def keep_comment_opening(replacement) #: Replacement
        content = comment_contents.find { replacement.from < _1.from && _1.from <= replacement.to }
        return replacement unless content

        tag = erb_tag_of(content)
        return replacement if replacement.from <= tag.from && tag.to <= replacement.to

        replacement.with(from: content.from, text: replacement.text.sub(/\A\s*#/, ""))
      end

      # The content of the ERB comment the replacement starts in (or at `#` of `<%#`) and goes beyond the end of
      # @rbs replacement: Replacement
      def comment_content_edited_to_end(replacement) #: CharRange?
        comment_contents.find do |content|
          content.from - 1 <= replacement.from && replacement.from < content.to && content.to < replacement.to
        end
      end

      # @rbs replacement: Replacement
      # @rbs from: Integer
      # @rbs to: Integer
      def trim_to(replacement, from: replacement.from, to: replacement.to) #: Replacement
        # An insertion at the edge of the content would be widened, not trimmed
        return replacement unless replacement.from <= from && to <= replacement.to

        trimmed = replacement.with(from:, to:)
        return replacement if whitespace?(trimmed.from, trimmed.to)
        return replacement unless whitespace?(replacement.from, from) && whitespace?(to, replacement.to)

        trimmed
      end

      # @rbs from: Integer
      # @rbs to: Integer
      def whitespace?(from, to) #: bool
        ruby_code[from, to - from].to_s.match?(/\A\s*\z/)
      end

      # @rbs buffer: ::Parser::Source::Buffer
      # @rbs replacements: Array[Replacement]
      def build_corrector(buffer, replacements) #: ::RuboCop::Cop::Corrector
        corrector = ::RuboCop::Cop::Corrector.new(buffer)
        replacements.each do |replacement|
          range = ::Parser::Source::Range.new(buffer, replacement.from, replacement.to)
          if range.empty?
            corrector.insert_before(range, replacement.text)
          else
            corrector.replace(range, replacement.text)
          end
        end
        corrector
      end
    end
  end
end
