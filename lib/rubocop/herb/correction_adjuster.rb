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
        from_content = content_starting_at(replacement.from)
        to_content = content_ending_at(replacement.to)
        return replacement if from_content.nil? == to_content.nil?

        if to_content
          trim_to(replacement, from: to_content.range.from)
        else
          trim_to(replacement, to: from_content.not_nil!.range.to)
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
